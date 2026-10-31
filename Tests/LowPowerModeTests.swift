// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LowPowerModeTests {
    static let profiles = """
    Battery Power:
     lowpowermode 1
    AC Power:
     lowpowermode 0
    """

    // The generated service is the production class with only its system
    // dependencies replaced. No test runs pmset or requests authorization.
    enum ProcessInfo {
        final class State { var isLowPowerModeEnabled = false }
        static let processInfo = State()
    }

    enum L10n {
        struct State { var language = AppLanguage.enUS }
        static let shared = State()
    }

    final class DispatchQueue {
        static let main = DispatchQueue(label: "main", qos: .userInitiated)
        static var pending: [() -> Void] = []
        init(label: String, qos: QualityOfService) {}
        func async(_ work: @escaping () -> Void) { Self.pending.append(work) }
        static func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
    }

    enum Shell {
        static var report = profiles
        static var status: Int32 = 0
        static var calls = 0
        static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
            precondition(path == "/usr/bin/pmset" && arguments == ["-g", "custom"])
            calls += 1
            return (status, report)
        }
    }

    enum AdminShell {
        static var approved = false
        static var commands: [String] = []
        static func runSync(_ command: String, prompt: String) -> Bool {
            precondition(!prompt.isEmpty)
            commands.append(command)
            if approved { ProcessInfo.processInfo.isLowPowerModeEnabled = command.hasSuffix(" 1") }
            return approved
        }
    }

    struct Snapshot {
        func takeRetainedValue() -> String { "snapshot" }
    }
    struct Source {
        let value: String
        func takeUnretainedValue() -> String { value }
    }
    static let kIOPSBatteryPowerValue = "Battery Power"
    static let kIOPSACPowerValue = "AC Power"
    static var effectiveSource: String? = kIOPSBatteryPowerValue
    static func IOPSCopyPowerSourcesInfo() -> Snapshot? { effectiveSource == nil ? nil : Snapshot() }
    static func IOPSGetProvidingPowerSourceType(_ snapshot: String) -> Source? {
        effectiveSource.map { Source(value: $0) }
    }

    static func run(_ suite: TestSuite) {
        for enabled in [false, true] {
            let value = enabled ? "1" : "0"
            suite.expect(LowPowerModeSupport.command(enabled: enabled, onBattery: true,
                                                     settingsReport: profiles)
                         == "/usr/bin/pmset -b lowpowermode \(value)",
                         "battery mode changes preserve the adapter profile")
            suite.expect(LowPowerModeSupport.command(enabled: enabled, onBattery: false,
                                                     settingsReport: profiles)
                         == "/usr/bin/pmset -c lowpowermode \(value)",
                         "adapter mode changes preserve the battery profile")
            suite.expect(LowPowerModeSupport.command(enabled: enabled, onBattery: false,
                                                     settingsReport: "Battery Power:\n lowpowermode 0\nAC Power:\n powermode 2")
                         == "/usr/bin/pmset -c powermode \(value)",
                         "High Power capable Macs use the selected profile's powermode key")
        }
        suite.expect(LowPowerModeSupport.command(enabled: false, onBattery: true,
                                                 settingsReport: "Battery Power:\n powermode 1")
                     == "/usr/bin/pmset -b powermode 0",
                     "turning Low Power Mode off returns its profile to automatic")
        suite.expect(LowPowerModeSupport.command(enabled: true, onBattery: true,
                                                 settingsReport: " AC Power: \r\n\tlowpowermode\t0\r\n Battery Power: \r\n\tpowermode\t0\r\n")
                     == "/usr/bin/pmset -b powermode 1",
                     "profile order, CRLF and ordinary whitespace do not affect selection")
        for report in ["", "lowpowermode 1", "Battery Power:\n sleep 1",
                       "AC Power:\n lowpowermode 1", "Battery Power:\n lowpowermode 2",
                       "Battery Power:\n powermode -1", "Battery Power:\n powermode 3",
                       "Battery Power:\n lowpowermode", "Battery Power:\n lowpowermode 1 extra",
                       "Battery Power:\n lowpowermode 1;whoami",
                       "Battery Power:\n lowpowermode$(whoami) 1",
                       "Battery Power:\nUPS Power:\n lowpowermode 1"] {
            suite.expect(LowPowerModeSupport.command(enabled: true, onBattery: true,
                                                     settingsReport: report) == nil,
                         "missing, unsupported and malformed profiles never produce a write: \(report)")
        }
        let english = FeatureStrings.lowPowerMode(.enUS)
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.lowPowerMode(language)
            let fields = [strings.title, strings.caption, strings.adminPrompt, strings.failed, strings.unavailable]
            suite.expect(fields.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                         "Low Power Mode text is complete in \(language.rawValue)")
            if language != .enUS {
                suite.expect(strings.title != english.title && strings.caption != english.caption,
                             "Low Power Mode labels and help are translated in \(language.rawValue)")
            }
        }

        let service = LowPowerModeService.shared
        func reset(source: String? = kIOPSBatteryPowerValue, enabled: Bool = false) {
            DispatchQueue.drain()
            ProcessInfo.processInfo.isLowPowerModeEnabled = enabled
            effectiveSource = source
            Shell.report = profiles
            Shell.status = 0
            Shell.calls = 0
            AdminShell.approved = false
            AdminShell.commands = []
            service.refresh()
        }

        reset()
        service.setEnabled(false)
        suite.expect(!service.isChanging && Shell.calls == 0 && AdminShell.commands.isEmpty,
                     "requesting the effective mode does not prompt or write")

        service.setEnabled(true)
        service.setEnabled(true)
        suite.expect(service.isChanging && !service.isEnabled,
                     "authorization keeps the current macOS state while rejecting repeated clicks")
        DispatchQueue.drain()
        suite.expect(!service.isChanging && !service.isEnabled && service.error == .failed
                     && AdminShell.commands == ["/usr/bin/pmset -b lowpowermode 1"],
                     "cancelled authorization leaves the switch off and completes the single request")

        ProcessInfo.processInfo.isLowPowerModeEnabled = true
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        suite.expect(service.isEnabled && service.error == nil,
                     "external system notifications refresh effective mode and clear an old error")

        reset(source: kIOPSACPowerValue)
        AdminShell.approved = true
        service.setEnabled(true)
        DispatchQueue.drain()
        suite.expect(service.isEnabled && !service.isChanging && service.error == nil
                     && AdminShell.commands == ["/usr/bin/pmset -c lowpowermode 1"],
                     "approved changes use the effective adapter profile and read macOS back")

        reset()
        Shell.report = "Battery Power:\n sleep 1"
        service.setEnabled(true)
        DispatchQueue.drain()
        suite.expect(service.error == .unavailable && !service.isChanging && AdminShell.commands.isEmpty,
                     "unsupported power profiles never request administrator access")

        reset()
        Shell.status = 1
        service.setEnabled(true)
        DispatchQueue.drain()
        suite.expect(service.error == .failed && !service.isChanging && AdminShell.commands.isEmpty,
                     "a failed settings read returns without attempting a write")

        for source in [nil, "UPS Power"] {
            reset(source: source)
            service.setEnabled(true)
            DispatchQueue.drain()
            suite.expect(service.error == .failed && !service.isChanging
                         && Shell.calls == 0 && AdminShell.commands.isEmpty,
                         "unknown sources do not guess a battery or adapter profile")
        }
        reset()
    }
}
