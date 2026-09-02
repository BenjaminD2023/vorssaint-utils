// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

final class ChargeControlService: ObservableObject {
    enum AccessState: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unavailable
    }

    static let shared = ChargeControlService()

    @Published private(set) var accessState: AccessState = .notRegistered
    @Published private(set) var snapshot: ChargeControlSnapshot = .idle
    @Published private(set) var profile: ChargeControlHardwareProfile?
    @Published private(set) var error: ChargeControlErrorCode?
    @Published private(set) var isWorking = false
    @Published private(set) var chargePercent: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var externalConnected = false
    @Published private(set) var hasBattery = PowerSampler.hasInternalBattery
    @Published private(set) var enabled = true
    @Published private(set) var limitPercent = ChargeControlPolicy.defaultLimit
    @Published private(set) var sailingEnabled = false
    @Published private(set) var sailingRangePercent = ChargeControlPolicy.defaultSailingRange
    @Published private(set) var mode: ChargeControlMode = .limit
    @Published private(set) var appliedGate: ChargeControlGate = .allowCharging
    @Published private(set) var now = Date()

    private let sampler = PowerSampler(smc: SMCClient())
    private let probeQueue = DispatchQueue(label: "com.vorssaint.charge-control.probe", qos: .utility)
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var panelIsVisible = false
    private var requestInFlight = false
    private var requestGeneration = 0
    private var evaluationCoalescer = ChargeControlEvaluationCoalescer()
    private var registrationAttemptedVersion: String?
    private var didRequestAuthorization = false
    private var sleepAssertion: IOPMAssertionID = 0
    private var lastAppliedGate: ChargeControlGate?

    private static var appService: SMAppService {
        SMAppService.daemon(plistName: ChargeControlIdentifiers.plistName)
    }

    private static var helperVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintChargeControlHelperVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? AppInfo.version
    }

    private init() {
        refreshFromDefaults()
        refreshAccessState()
    }

    deinit {
        connection?.invalidate()
        timer?.invalidate()
        releaseSleepAssertion()
    }

    var isCalibrating: Bool {
        if case .calibration = mode { return true }
        return false
    }

    var isDischargingToLimit: Bool {
        if case .dischargeToLimit = mode { return true }
        return false
    }

    var isToppingUp: Bool {
        if case .topUp = mode { return true }
        return false
    }

    var holdRemainingSeconds: TimeInterval? {
        guard case .calibration(let state) = mode else { return nil }
        return ChargeControlPolicy.holdRemaining(state: state, now: now)
    }

    var calibrationPhase: ChargeCalibrationPhase? {
        guard case .calibration(let state) = mode else { return nil }
        return state.phase
    }

    static func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        shared.restoreCharging()
    }

    func syncWithPreferences() {
        refreshFromDefaults()
        if AppFeature.chargeControl.isAvailable, hasBattery {
            if UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) {
                restoreCharging()
            }
            startTimerIfNeeded()
            refresh()
        } else {
            cancelTransientModes()
            restoreThenUnregister()
        }
    }

    func panelDidAppear() {
        panelIsVisible = true
        refresh()
        if AppFeature.chargeControl.isAvailable, hasBattery, enabled {
            ensureHelperForControl()
        }
        startTimerIfNeeded()
    }

    func panelDidDisappear() {
        panelIsVisible = false
        stopIdleWorkIfPossible()
    }

    func refresh() {
        refreshFromDefaults()
        refreshAccessState()
        sampleBattery()
        if accessState == .enabled {
            guard !replaceRegistrationIfNeeded() else { return }
            requestStatus()
        } else {
            refreshLocalProbe()
        }
        evaluate()
    }

    func authorize() {
        refreshAccessState()
        switch accessState {
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .enabled:
            requestStatus()
            evaluate()
        case .unavailable, .notRegistered:
            isWorking = true
            do {
                try Self.appService.register()
                UserDefaults.standard.set(Self.helperVersion,
                                          forKey: DefaultsKey.chargeControlHelperVersion)
                refreshAccessState()
                isWorking = false
                if accessState == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if accessState == .enabled {
                    requestStatus()
                    evaluate()
                } else {
                    self.error = .helperUnavailable
                }
            } catch {
                isWorking = false
                refreshAccessState()
                if accessState == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    self.error = .helperUnavailable
                }
            }
        }
        startTimerIfNeeded()
    }

    /// Register the helper once when the user sets a limit. Login Items
    /// approval is a system sheet; repeating it on every slider tick is noise.
    private func ensureHelperForControl() {
        refreshAccessState()
        guard accessState != .enabled else { return }
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        authorize()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.chargeLimitEnabled)
        self.enabled = enabled
        if !enabled {
            cancelTransientModes()
        } else {
            ensureHelperForControl()
        }
        evaluate()
    }

    func setLimit(_ percent: Int) {
        let cap = ChargeControlPolicy.sanitizedLimit(percent)
        UserDefaults.standard.set(cap, forKey: DefaultsKey.chargeLimitPercent)
        limitPercent = cap
        setSailingRange(sailingRangePercent, evaluateAfterChange: false)
        if accessState != .enabled { ensureHelperForControl() }
        evaluate(refreshBattery: false)
    }

    func setSailingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.chargeSailingEnabled)
        sailingEnabled = enabled
        ensureHelperForControl()
        evaluate()
    }

    func setSailingRange(_ percent: Int) {
        setSailingRange(percent, evaluateAfterChange: true)
    }

    func startDischargeToLimit() {
        guard profile?.supportsDischarge == true,
              let charge = chargePercent, charge > limitPercent else { return }
        guard accessState == .enabled else { authorize(); return }
        mode = .dischargeToLimit
        takeSleepAssertion()
        evaluate()
    }

    func stopDischarge() {
        guard isDischargingToLimit else { return }
        mode = .limit
        releaseSleepAssertion()
        evaluate()
    }

    func startTopUp() {
        guard limitPercent < ChargeControlPolicy.maximumLimit,
              (chargePercent ?? 0) < ChargeControlPolicy.maximumLimit else { return }
        guard accessState == .enabled else { authorize(); return }
        mode = .topUp
        releaseSleepAssertion()
        evaluate()
    }

    func stopTopUp() {
        guard isToppingUp else { return }
        mode = .limit
        evaluate()
    }

    func startCalibration() {
        guard profile?.supportsDischarge == true, externalConnected else { return }
        guard accessState == .enabled else { authorize(); return }
        mode = .calibration(ChargeControlPolicy.startCalibration(chargePercent: chargePercent ?? 0,
                                                                 savedLimit: limitPercent))
        takeSleepAssertion()
        evaluate()
    }

    func cancelCalibration() {
        guard isCalibrating else { return }
        mode = .limit
        releaseSleepAssertion()
        evaluate()
    }

    func restoreCharging() {
        restoreCharging(supersedingCurrentRequest: false)
    }

    static func restoreBeforeTerminationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        shared.restoreBeforeTermination()
    }

    @discardableResult
    static func restoreAndUnregisterForRemoval() -> Bool {
        let service = appService
        guard service.status == .enabled else {
            guard service.status != .notRegistered else { return true }
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded)
            else { return false }
            return unregisterForRemoval(service)
        }
        let connection = NSXPCConnection(machServiceName: ChargeControlIdentifiers.helperID,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlXPCProtocol.self)
        connection.setCodeSigningRequirement(ChargeControlIdentifiers.helperCodeRequirement)
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var restored = false
        connection.activate()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() }
            as? ChargeControlXPCProtocol
        guard let proxy else {
            connection.invalidate()
            return false
        }
        proxy.restoreNormal { data in
            if let response = ChargeControlIPC.decodeResponse(data) {
                resultLock.withLock {
                    restored = response.succeeded && response.snapshot.gate == .allowCharging
                }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20)
        connection.invalidate()
        guard resultLock.withLock({ restored }) else { return false }
        return unregisterForRemoval(service)
    }

    private static func unregisterForRemoval(_ service: SMAppService) -> Bool {
        do {
            try service.unregister()
            return true
        } catch {
            return false
        }
    }

    private func evaluate(refreshBattery: Bool = true) {
        if refreshBattery { sampleBattery() }
        advanceCalibrationIfNeeded()
        settleDischargeIfNeeded()
        settleTopUpIfNeeded()

        let active = AppFeature.chargeControl.isAvailable && hasBattery && enabled
        let needsControl = active || isCalibrating || isDischargingToLimit || isToppingUp
        guard needsControl else {
            if lastAppliedGate != .allowCharging || appliedGate != .allowCharging {
                applyGate(.allowCharging)
            }
            releaseSleepAssertion()
            stopIdleWorkIfPossible()
            return
        }
        guard accessState == .enabled else { return }
        let gate = ChargeControlPolicy.desiredGate(
            chargePercent: chargePercent ?? 0,
            limit: limitPercent,
            sailingRange: sailingEnabled ? sailingRangePercent : nil,
            wasInhibited: appliedGate == .inhibitCharging,
            mode: mode,
            family: profile?.family ?? snapshot.profile?.family)
        applyGate(gate)
        startTimerIfNeeded()
    }

    private func advanceCalibrationIfNeeded() {
        guard case .calibration(let state) = mode, let charge = chargePercent else { return }
        now = Date()
        if let next = ChargeControlPolicy.advanceCalibration(state, chargePercent: charge, now: now) {
            if next != state { mode = .calibration(next) }
        } else {
            mode = .limit
            releaseSleepAssertion()
        }
    }

    private func settleDischargeIfNeeded() {
        guard isDischargingToLimit, let charge = chargePercent else { return }
        if charge <= limitPercent {
            mode = .limit
            releaseSleepAssertion()
        }
    }

    private func settleTopUpIfNeeded() {
        guard isToppingUp, let charge = chargePercent else { return }
        if charge >= ChargeControlPolicy.maximumLimit {
            mode = .limit
        }
    }

    private func applyGate(_ gate: ChargeControlGate) {
        guard accessState == .enabled else { return }
        guard !evaluationCoalescer.deferIfBusy(requestInFlight) else { return }
        let generation = beginRequest()
        let requestLimit = isToppingUp ? ChargeControlPolicy.maximumLimit : limitPercent
        let request = ChargeControlRequest(gate: gate, limitPercent: requestLimit)
        if gate != .allowCharging {
            UserDefaults.standard.set(true, forKey: DefaultsKey.chargeControlRecoveryNeeded)
        }
        send { proxy, reply in
            proxy.apply(ChargeControlIPC.encode(request), withReply: reply)
        } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded {
                self.lastAppliedGate = gate
                self.appliedGate = gate
                if gate == .allowCharging {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
                }
            }
        }
    }

    private func requestStatus() {
        guard !requestInFlight else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.status(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            UserDefaults.standard.set(Self.helperVersion, forKey: DefaultsKey.chargeControlHelperVersion)
            if response.succeeded, response.snapshot.gate == .allowCharging {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
            }
        }
    }

    private func heartbeat() {
        guard appliedGate != .allowCharging, !requestInFlight, !isWorking else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.heartbeat(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded, response.snapshot.gate == .allowCharging,
               self.isCalibrating || self.isDischargingToLimit {
                self.mode = .limit
                self.releaseSleepAssertion()
            }
        }
    }

    private func restoreCharging(supersedingCurrentRequest: Bool) {
        guard supersedingCurrentRequest || !isWorking else { return }
        refreshAccessState()
        guard accessState == .enabled else { return }
        let generation = beginRequest()
        isWorking = true
        send { proxy, reply in proxy.restoreNormal(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            self.isWorking = false
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded, response.snapshot.gate == .allowCharging {
                self.lastAppliedGate = .allowCharging
                self.appliedGate = .allowCharging
                UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
                if !AppFeature.chargeControl.isAvailable { self.unregisterHelper() }
                self.stopIdleWorkIfPossible()
            }
        }
    }

    private func restoreBeforeTermination() {
        send { proxy, reply in proxy.restoreNormal(withReply: reply) } completion: { response in
            if let response, response.succeeded, response.snapshot.gate == .allowCharging {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
            }
        }
        connection?.invalidate()
        connection = nil
        releaseSleepAssertion()
    }

    private func restoreThenUnregister() {
        refreshAccessState()
        guard accessState != .notRegistered else { return }
        if accessState != .enabled {
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else {
                error = .authorizationRequired
                return
            }
            unregisterHelper()
            return
        }
        restoreCharging(supersedingCurrentRequest: true)
    }

    private func unregisterHelper() {
        do {
            try Self.appService.unregister()
            UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlHelperVersion)
            refreshAccessState()
        } catch {
            self.error = .helperUnavailable
        }
    }

    private func send(_ operation: @escaping (ChargeControlXPCProtocol, @escaping (Data) -> Void) -> Void,
                      completion: @escaping (ChargeControlResponse?) -> Void) {
        var finished = false
        let finish: (ChargeControlResponse?) -> Void = { response in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(response)
            }
        }
        guard let proxy = proxy(errorHandler: { [weak self] failedConnection in
            DispatchQueue.main.async {
                if self?.connection === failedConnection {
                    failedConnection.invalidate()
                    self?.connection = nil
                }
                finish(nil)
            }
        }) else {
            finish(nil)
            return
        }
        operation(proxy) { data in
            finish(ChargeControlIPC.decodeResponse(data))
        }
    }

    private func proxy(errorHandler: @escaping (NSXPCConnection) -> Void) -> ChargeControlXPCProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: ChargeControlIdentifiers.helperID,
                                             options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlXPCProtocol.self)
            connection.setCodeSigningRequirement(ChargeControlIdentifiers.helperCodeRequirement)
            connection.interruptionHandler = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection, self?.connection === connection else { return }
                    connection.invalidate()
                    self?.connection = nil
                }
            }
            connection.invalidationHandler = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection else { return }
                    if self?.connection === connection { self?.connection = nil }
                }
            }
            connection.activate()
            self.connection = connection
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler { _ in errorHandler(connection) }
            as? ChargeControlXPCProtocol
    }

    private func apply(_ response: ChargeControlResponse) {
        let gateChanged = response.succeeded && appliedGate != response.snapshot.gate
        snapshot = response.snapshot
        if let profile = response.snapshot.profile { self.profile = profile }
        error = response.error
        if response.succeeded { appliedGate = response.snapshot.gate }
        now = Date()
        if gateChanged {
            SystemMonitor.shared.powerStateDidChange()
            for delay in ChargeControlPolicy.postGateRefreshDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.sampleBattery(notifyMonitor: true)
                }
            }
        }
    }

    private func beginRequest() -> Int {
        requestGeneration += 1
        requestInFlight = true
        return requestGeneration
    }

    private func finishRequest(_ generation: Int) -> Bool {
        guard generation == requestGeneration else { return false }
        requestInFlight = false
        if evaluationCoalescer.consumePending() {
            DispatchQueue.main.async { [weak self] in
                self?.evaluate(refreshBattery: false)
            }
        }
        return true
    }

    private func refreshAccessState() {
        switch Self.appService.status {
        case .notRegistered: accessState = .notRegistered
        case .enabled: accessState = .enabled
        case .requiresApproval: accessState = .requiresApproval
        case .notFound: accessState = .unavailable
        @unknown default: accessState = .unavailable
        }
    }

    private func replaceRegistrationIfNeeded() -> Bool {
        let installed = UserDefaults.standard.string(forKey: DefaultsKey.chargeControlHelperVersion) ?? ""
        let current = Self.helperVersion
        guard !installed.isEmpty, installed != current,
              registrationAttemptedVersion != current,
              !UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return false }
        registrationAttemptedVersion = current
        isWorking = true
        Self.appService.unregister { error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self.isWorking = false
                    self.error = .helperUnavailable
                    return
                }
                do {
                    try Self.appService.register()
                    UserDefaults.standard.set(current, forKey: DefaultsKey.chargeControlHelperVersion)
                    self.isWorking = false
                    self.refreshAccessState()
                    if self.accessState == .enabled { self.requestStatus() }
                } catch {
                    self.isWorking = false
                    self.refreshAccessState()
                    self.error = .helperUnavailable
                }
            }
        }
        return true
    }

    private func refreshLocalProbe() {
        probeQueue.async {
            let profile = ChargeControlHardware()?.profile
            DispatchQueue.main.async {
                guard self.accessState != .enabled else { return }
                self.profile = profile
                // Unprivileged code cannot see every charging SMC key. Only the
                // helper may declare the Mac unsupported; until then offer Allow.
                if profile == nil, !PowerSampler.hasInternalBattery {
                    self.error = .noBattery
                }
            }
        }
    }

    private func sampleBattery(notifyMonitor: Bool = false) {
        hasBattery = PowerSampler.hasInternalBattery
        guard hasBattery else {
            chargePercent = nil
            isCharging = false
            externalConnected = false
            return
        }
        let reading = sampler.sample()
        let stateChanged = isCharging != reading.isCharging
            || externalConnected != reading.externalConnected
        chargePercent = reading.chargePercent
        isCharging = reading.isCharging
        externalConnected = reading.externalConnected
        if stateChanged || notifyMonitor { SystemMonitor.shared.powerStateDidChange() }
    }

    private func refreshFromDefaults() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: DefaultsKey.chargeLimitEnabled) as? Bool ?? true
        limitPercent = ChargeControlPolicy.sanitizedLimit(defaults.integer(forKey: DefaultsKey.chargeLimitPercent))
        sailingEnabled = defaults.bool(forKey: DefaultsKey.chargeSailingEnabled)
        sailingRangePercent = ChargeControlPolicy.sanitizedSailingRange(
            defaults.integer(forKey: DefaultsKey.chargeSailingRangePercent),
            limit: limitPercent)
        hasBattery = PowerSampler.hasInternalBattery
    }

    private func setSailingRange(_ percent: Int, evaluateAfterChange: Bool) {
        let range = ChargeControlPolicy.sanitizedSailingRange(percent, limit: limitPercent)
        UserDefaults.standard.set(range, forKey: DefaultsKey.chargeSailingRangePercent)
        sailingRangePercent = range
        if evaluateAfterChange {
            if accessState != .enabled { ensureHelperForControl() }
            evaluate(refreshBattery: false)
        }
    }

    private func cancelTransientModes() {
        if isCalibrating || isDischargingToLimit || isToppingUp {
            mode = .limit
            releaseSleepAssertion()
        }
    }

    private func startTimerIfNeeded() {
        let active = AppFeature.chargeControl.isAvailable && hasBattery
            && (enabled || isCalibrating || isDischargingToLimit || isToppingUp)
        guard panelIsVisible || active
                || UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: ChargeControlPolicy.pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            if self.accessState != .enabled {
                self.refreshAccessState()
                if self.accessState == .enabled { self.requestStatus() }
            }
            if self.appliedGate != .allowCharging { self.heartbeat() }
            self.evaluate()
        }
    }

    private func stopIdleWorkIfPossible() {
        guard !panelIsVisible,
              !(AppFeature.chargeControl.isAvailable && hasBattery && enabled),
              !isCalibrating, !isDischargingToLimit, !isToppingUp,
              !UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        timer?.invalidate()
        timer = nil
    }

    private func takeSleepAssertion() {
        guard sleepAssertion == 0 else { return }
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Vorssaint battery calibration" as CFString,
            &assertionID)
        if result == kIOReturnSuccess { sleepAssertion = assertionID }
    }

    private func releaseSleepAssertion() {
        guard sleepAssertion != 0 else { return }
        IOPMAssertionRelease(sleepAssertion)
        sleepAssertion = 0
    }
}
