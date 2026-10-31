// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import IOKit.ps

final class LowPowerModeService: ObservableObject {
    static let shared = LowPowerModeService()

    enum ChangeError {
        case failed, unavailable
    }

    @Published private(set) var isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var isChanging = false
    @Published private(set) var error: ChangeError?

    private let queue = DispatchQueue(label: "com.vorssaint.low-power-mode", qos: .userInitiated)
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        error = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        refresh()
        guard enabled != isEnabled else { return }
        isChanging = true
        error = nil
        let prompt = FeatureStrings.lowPowerMode(L10n.shared.language).adminPrompt

        queue.async {
            // Read the effective source, independent of charging/discharge
            // controls and the UI's potentially older battery snapshot.
            guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?,
                  source == kIOPSBatteryPowerValue || source == kIOPSACPowerValue else {
                self.finish(error: .failed)
                return
            }
            let report = Shell.run("/usr/bin/pmset", ["-g", "custom"])
            guard report.status == 0 else {
                self.finish(error: .failed)
                return
            }
            guard let command = LowPowerModeSupport.command(enabled: enabled,
                                                            onBattery: source == kIOPSBatteryPowerValue,
                                                            settingsReport: report.output) else {
                self.finish(error: .unavailable)
                return
            }
            let changed = AdminShell.runSync(command, prompt: prompt)
            self.finish(error: changed ? nil : .failed)
        }
    }

    private func finish(error: ChangeError?) {
        DispatchQueue.main.async {
            // The switch always reflects macOS, including cancelled or failed
            // authorization. A later system notification also refreshes it.
            self.refresh()
            self.error = error
            self.isChanging = false
        }
    }
}
