// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LowPowerModeSupport {
    /// Only change the active power profile. Macs with High Power Mode report
    /// `powermode` instead of `lowpowermode`; both use 1 for Low Power Mode.
    static func command(enabled: Bool, onBattery: Bool, settingsReport: String) -> String? {
        let profile = onBattery ? "Battery Power:" : "AC Power:"
        var inProfile = false
        for line in settingsReport.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(":") {
                inProfile = trimmed == profile
                continue
            }
            guard inProfile else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2,
                  (fields[0] == "lowpowermode" && ["0", "1"].contains(fields[1]))
                    || (fields[0] == "powermode" && ["0", "1", "2"].contains(fields[1]))
            else { continue }
            return "/usr/bin/pmset \(onBattery ? "-b" : "-c") \(fields[0]) \(enabled ? "1" : "0")"
        }
        return nil
    }
}
