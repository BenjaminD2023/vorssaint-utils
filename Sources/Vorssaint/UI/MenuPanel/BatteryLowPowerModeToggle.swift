// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BatteryLowPowerModeToggle: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = LowPowerModeService.shared

    private var strings: LowPowerModeFeatureStrings {
        FeatureStrings.lowPowerMode(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.55)
            HStack(spacing: 8) {
                Text(strings.title)
                    .font(.system(size: 11))
                Spacer(minLength: 0)
                if service.isChanging {
                    ProgressView().controlSize(.mini)
                }
                Toggle(strings.title, isOn: Binding(
                    get: { service.isEnabled },
                    set: { service.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(service.isChanging)
                .accessibilityLabel(strings.title)
            }
            .help(strings.caption)

            if let error = service.error {
                Text(error == .unavailable ? strings.unavailable : strings.failed)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { service.refresh() }
    }
}
