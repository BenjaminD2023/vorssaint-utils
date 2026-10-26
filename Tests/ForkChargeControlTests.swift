// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Fork charging behavior stays covered separately from upstream monitor tests.
enum ForkChargeControlTests {
    static func run(_ suite: TestSuite) {
        let expect: (Bool, String) -> Void = { suite.expect($0, $1) }
        expect(MetricFormat.batteryIsCharging(systemReported: false,
                                              registryReported: true,
                                              amperageMilliamps: 0,
                                              externalConnected: true)
                && !MetricFormat.batteryIsCharging(systemReported: true,
                                                   registryReported: false,
                                                   amperageMilliamps: 1,
                                                   externalConnected: true)
                && !MetricFormat.batteryIsCharging(systemReported: false,
                                                   registryReported: nil,
                                                   amperageMilliamps: 1,
                                                   externalConnected: true)
                && MetricFormat.batteryIsCharging(systemReported: nil,
                                                  registryReported: nil,
                                                  amperageMilliamps: 1,
                                                  externalConnected: true)
                && !MetricFormat.batteryIsCharging(systemReported: true,
                                                   registryReported: true,
                                                   amperageMilliamps: 1,
                                                   externalConnected: false),
               "the direct battery flag wins while disconnect always clears charging")
        expect(ChargeControlPolicy.sanitizedLimit(80) == 80
                && ChargeControlPolicy.sanitizedLimit(20) == 20
                && ChargeControlPolicy.sanitizedLimit(100) == 100
                && ChargeControlPolicy.sanitizedLimit(5) == 80
                && Defaults.sanitizedChargeLimit(12) == 80,
               "charge limits stay inside 20...100 and fall back to 80")
        expect(ChargeControlPolicy.sanitizedSailingRange(5, limit: 90) == 5
                && ChargeControlPolicy.sanitizedSailingRange(0, limit: 90) == 1
                && ChargeControlPolicy.sanitizedSailingRange(90, limit: 90) == 80
                && ChargeControlPolicy.maximumSailingRange(limit: 20) == 10,
               "sailing ranges stay between one percent and the ten-percent battery floor")
        expect(ChargeControlPolicy.postGateRefreshDelays == [0.25, 0.75, 1.5],
               "charge-gate changes recheck battery telemetry three times within 1.5 seconds")
        expect(ChargeLimitBarSupport.filledSegmentCount(for: 0) == 0
                && ChargeLimitBarSupport.filledSegmentCount(for: 63) == 13
                && ChargeLimitBarSupport.filledSegmentCount(for: 100) == 20
                && ChargeLimitBarSupport.targetFraction(for: 80) == 0.8
                && !ChargeLimitBarSupport.isAboveLimit(segment: 15, limit: 80)
                && ChargeLimitBarSupport.isAboveLimit(segment: 16, limit: 80),
               "charge bars map level and limit onto twenty 5% segments")
        var evaluationCoalescer = ChargeControlEvaluationCoalescer()
        let deferredWhileBusy = evaluationCoalescer.deferIfBusy(true)
            && evaluationCoalescer.deferIfBusy(true)
        expect(!evaluationCoalescer.deferIfBusy(false)
                && deferredWhileBusy
                && evaluationCoalescer.consumePending()
                && !evaluationCoalescer.consumePending(),
               "charge-control request bursts produce one trailing evaluation")
        expect(BatteryPowerState.adapterConnected(bytes: [0xFF]) == false
                && BatteryPowerState.adapterConnected(bytes: [0]) == true
                && BatteryPowerState.adapterConnected(bytes: [2]) == true,
               "the physical adapter flag distinguishes unplugged from every valid port, including zero")
        expect(BatteryPowerState.adapterConnected(bytes: nil) == nil
                && BatteryPowerState.adapterConnected(bytes: []) == nil
                && BatteryPowerState.adapterConnected(bytes: [0, 0]) == nil
                && BatteryPowerState.adapterConnected(bytes: [0xFE]) == nil,
               "missing or invalid physical adapter flags fall back to system telemetry")
        expect(BatteryPowerState.flag(bytes: [0]) == false
                && BatteryPowerState.flag(bytes: [1]) == true
                && BatteryPowerState.flag(bytes: [8], enabledValue: 8) == true
                && BatteryPowerState.flag(bytes: [2]) == nil
                && BatteryPowerState.flag(bytes: nil) == nil
                && BatteryPowerState.flag(bytes: [1, 0]) == nil,
               "controller flags accept only the known one-byte encodings")
        let liveCharging = BatteryPowerState(adapterConnected: true, isCharging: true)
            .resolve(externalConnected: false, isCharging: false)
        expect(liveCharging.externalConnected && liveCharging.isCharging,
               "live charging immediately supersedes stale unplugged driver flags")
        let liveHolding = BatteryPowerState(adapterConnected: true, isCharging: false)
            .resolve(externalConnected: true, isCharging: true)
        expect(liveHolding.externalConnected && !liveHolding.isCharging,
               "live holding immediately supersedes stale charging driver flags")
        let liveUnplugged = BatteryPowerState(adapterConnected: false, isCharging: true)
            .resolve(externalConnected: true, isCharging: true)
        expect(!liveUnplugged.externalConnected && !liveUnplugged.isCharging,
               "unplugging clears charging even before the controller charging flag settles")
        let forcedState = BatteryPowerState(adapterConnected: true, isCharging: false, isDischarging: true)
        let liveDischarging = forcedState.resolve(externalConnected: true, isCharging: true)
        expect(forcedState.adapterConnected == true
                && !liveDischarging.externalConnected && !liveDischarging.isCharging,
               "forced discharge keeps physical presence separate from battery-powered state")
        let fallbackState = BatteryPowerState().resolve(externalConnected: true, isCharging: false)
        expect(fallbackState.externalConnected && !fallbackState.isCharging,
               "unsupported controller keys preserve system-reported holding")
        expect(ChargeControlRequest(gate: .inhibitCharging, limitPercent: 60)
                != ChargeControlRequest(gate: .inhibitCharging, limitPercent: 80),
               "request deduplication distinguishes Intel firmware limits with the same gate")
        expect(ChargeControlPolicy.desiredGate(chargePercent: 81, limit: 80,
                                               wasInhibited: false, mode: .limit,
                                               family: .appleSiliconCHT) == .inhibitCharging,
               "Apple Silicon stops charging at the cap")
        expect(ChargeControlPolicy.desiredGate(chargePercent: 81, limit: 80,
                                               wasInhibited: true, mode: .limit,
                                               family: .appleSiliconCHT,
                                               externalConnected: false) == .allowCharging
                && ChargeControlPolicy.desiredGate(chargePercent: 79, limit: 80,
                                                   wasInhibited: false, mode: .limit,
                                                   family: .appleSiliconCHT) == .allowCharging,
               "unplugging releases the gate so reconnecting below the cap charges immediately")
        expect(ChargeControlPolicy.desiredGate(chargePercent: 79, limit: 80,
                                               wasInhibited: true, mode: .limit,
                                               family: .appleSiliconCHT) == .inhibitCharging
                && ChargeControlPolicy.desiredGate(chargePercent: 78, limit: 80,
                                                   wasInhibited: true, mode: .limit,
                                                   family: .appleSiliconCHT) == .allowCharging,
               "Apple Silicon uses a 2 percent hysteresis before charging again")
        expect(ChargeControlPolicy.desiredGate(chargePercent: 86, limit: 90,
                                               sailingRange: 5, wasInhibited: true,
                                               mode: .limit, family: .appleSiliconCHT) == .inhibitCharging
                && ChargeControlPolicy.desiredGate(chargePercent: 85, limit: 90,
                                                   sailingRange: 5, wasInhibited: true,
                                                   mode: .limit, family: .appleSiliconCHT) == .allowCharging
                && ChargeControlPolicy.desiredGate(chargePercent: 84, limit: 90,
                                                   sailingRange: 5, wasInhibited: true,
                                                   mode: .limit, family: .appleSiliconCHT) == .allowCharging
                && ChargeControlPolicy.desiredGate(chargePercent: 90, limit: 90,
                                                   sailingRange: 5, wasInhibited: false,
                                                   mode: .limit, family: .intelBCLM) == .inhibitCharging
                && ChargeControlPolicy.desiredGate(chargePercent: 84, limit: 90,
                                                   sailingRange: 5, wasInhibited: true,
                                                   mode: .limit, family: .intelBCLM) == .allowCharging,
               "a five-percent sailing range at 90 resumes at 85")
        expect(ChargeControlPolicy.desiredGate(chargePercent: 70, limit: 80,
                                               wasInhibited: false, mode: .limit,
                                               family: .intelBCLM) == .inhibitCharging,
               "Intel writes the firmware cap")
        expect(ChargeControlPolicy.desiredGate(chargePercent: 90, limit: 80,
                                               wasInhibited: false, mode: .dischargeToLimit,
                                               family: .appleSiliconCHT) == .forceDischarge,
               "manual discharge overrides the cap")
        for percent in [0, 10, 79, 80, 90, 100] {
            for connected in [false, true] {
                expect(ChargeControlPolicy.desiredGate(chargePercent: percent, limit: 90,
                       wasInhibited: true, mode: .dischargeToLimit, family: .nativePowerUI,
                       externalConnected: connected) == (connected ? .forceDischarge : .allowCharging),
                       "manual discharge ignores the limit; unplugged Macs need no adapter write")
            }
        }
        expect(ChargeControlPolicy.desiredGate(chargePercent: 90, limit: 80,
                                               wasInhibited: true, mode: .topUp,
                                               family: .appleSiliconCHT) == .allowCharging
                && ChargeControlPolicy.desiredGate(chargePercent: 70, limit: 80,
                                                   wasInhibited: true, mode: .topUp,
                                                   family: .intelBCLM) == .allowCharging,
               "top up charges past the cap until 100%")
        for percent in [79, 80, 90, 99] {
            expect(ChargeControlPolicy.desiredGate(chargePercent: percent, limit: 80,
                                                   wasInhibited: true, mode: .topUp,
                                                   family: .nativePowerUI) == .allowCharging,
                   "native Top Up releases holding both below and above the saved cap")
        }
        let startedLow = ChargeControlPolicy.startCalibration(chargePercent: 72, savedLimit: 80)
        expect(startedLow.phase == .chargingToFull && startedLow.savedLimit == 80,
               "calibration charges to full first when the battery is not already at 100%")
        expect(ChargeControlPolicy.startCalibration(chargePercent: 100, savedLimit: 80).phase
                == .dischargingToFloor,
               "calibration skips the first charge when the battery is already full")
        let calNow = Date(timeIntervalSince1970: 1_000)
        expect(ChargeControlPolicy.advanceCalibration(startedLow, chargePercent: 100, now: calNow)?.phase
                == .dischargingToFloor,
               "the first charge hands off to the discharge to 10%")
        expect(ChargeControlPolicy.advanceCalibration(
            ChargeCalibrationState(phase: .holdingAtFull, holdStartedAt: calNow, savedLimit: 80),
            chargePercent: 100, now: calNow.addingTimeInterval(60 * 60),
            holdDuration: 60 * 60)?.phase == .restoringLimit,
               "the hold returns to the saved limit")
        expect(ChargeControlPolicy.advanceCalibration(
            ChargeCalibrationState(phase: .restoringLimit, holdStartedAt: nil, savedLimit: 80),
            chargePercent: 80, now: calNow) == nil,
               "calibration finishes once the battery is back at the saved limit")
        expect(ChargeControlPolicy.restoreReason(hasActiveGate: true, heartbeatAge: 8)
                && !ChargeControlPolicy.restoreReason(hasActiveGate: true, heartbeatAge: 2)
                && !ChargeControlPolicy.restoreReason(hasActiveGate: false, heartbeatAge: 8),
               "every active charge gate restores if the app heartbeat is lost")
        expect(ChargeControlPolicy.paddedSMCBytes([0x01, 0x00, 0x00, 0x00], to: 4)
                == [0x01, 0x00, 0x00, 0x00]
                && ChargeControlPolicy.paddedSMCBytes([0x01, 0x00, 0x00, 0x00], to: 1) == [0x01]
                && ChargeControlPolicy.paddedSMCBytes([0x01], to: 4) == [0x01, 0x00, 0x00, 0x00],
               "SMC writes pad or trim to the key's reported size")


        let domain = "com.vorssaint.tests.chargeSailingRange"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(90, forKey: DefaultsKey.chargeLimitPercent)
        defaults.set(85, forKey: DefaultsKey.chargeSailingMinimumPercent)
        Defaults.migrateChargeSailingRange(in: defaults)
        expect(defaults.integer(forKey: DefaultsKey.chargeSailingRangePercent) == 5
                && defaults.object(forKey: DefaultsKey.chargeSailingMinimumPercent) == nil,
               "legacy absolute sailing minima migrate to a range below the saved cap")
        defaults.set(7, forKey: DefaultsKey.chargeSailingRangePercent)
        defaults.set(60, forKey: DefaultsKey.chargeSailingMinimumPercent)
        Defaults.migrateChargeSailingRange(in: defaults)
        expect(defaults.integer(forKey: DefaultsKey.chargeSailingRangePercent) == 7
                && defaults.object(forKey: DefaultsKey.chargeSailingMinimumPercent) == nil,
               "a migrated sailing range is never overwritten by stale legacy state")

        let backupKeys = SettingsBackupSupport.exportKeys()
        expect(backupKeys.contains(DefaultsKey.chargeLimitEnabled)
                && backupKeys.contains(DefaultsKey.chargeLimitPercent)
                && backupKeys.contains(DefaultsKey.chargeSailingEnabled)
                && backupKeys.contains(DefaultsKey.chargeSailingRangePercent)
                && !backupKeys.contains(DefaultsKey.chargeSailingMinimumPercent)
                && backupKeys.contains(DefaultsKey.panelShowChargeControl)
                && !backupKeys.contains(DefaultsKey.chargeControlRecoveryNeeded)
                && !backupKeys.contains(DefaultsKey.chargeControlHelperVersion),
               "charge settings travel with backups while helper recovery stays on one Mac")
        expect((Defaults.registeredDefaults[DefaultsKey.chargeLimitPercent] as? Int) == 80
                && (Defaults.registeredDefaults[DefaultsKey.chargeSailingEnabled] as? Bool) == false
                && (Defaults.registeredDefaults[DefaultsKey.chargeSailingRangePercent] as? Int) == 5,
               "charge control begins at 80 percent with optional sailing disabled")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.chargeControl(language)
            LocalizationTests.check(strings, against: FeatureStrings.chargeControl(.enUS),
                                    name: "charge control " + language.rawValue, suite: suite)
        }
    }
}
