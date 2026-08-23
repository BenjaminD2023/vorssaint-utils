// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ChargeControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    var collapsible = true

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        PanelSection(.chargeControl, title: strings.title, collapsible: collapsible) {
            ChargeControlCardContent(compact: true)
                .panelCard()
                .onAppear { service.panelDidAppear() }
                .onDisappear { service.panelDidDisappear() }
        }
    }
}

struct ChargeControlCardContent: View {
    var compact = false
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    @Environment(\.colorScheme) private var colorScheme

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            header
            if service.hasBattery {
                dial
                limitSlider
                if let message = stateMessage {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
                if !compact {
                    calibrationBlock
                    Text(strings.safetyCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.secondary.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                } else if service.isCalibrating {
                    compactCalibration
                }
            } else {
                Text(strings.noBattery)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: service.isCharging)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(strings.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(statusColor)
            }
            Spacer()
            if service.isWorking { ProgressView().controlSize(.small) }
        }
    }

    private var dial: some View {
        HStack {
            Spacer()
            ChargeLimitDial(
                charge: Double(service.chargePercent ?? 0) / 100,
                limit: Double(service.limitPercent) / 100,
                statusColor: statusColor,
                chargeLabel: "\(service.chargePercent ?? 0)",
                statusLabel: statusText
            )
            .frame(width: compact ? 148 : 176, height: compact ? 148 : 176)
            Spacer()
        }
        .padding(.vertical, compact ? 2 : 6)
    }

    private var limitSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strings.limitLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(service.limitPercent)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
            }
            ChargeLimitSlider(
                value: Binding(get: { Double(service.limitPercent) },
                               set: { service.setLimit(Int($0.rounded())) }),
                range: Double(ChargeControlPolicy.minimumLimit)...Double(ChargeControlPolicy.maximumLimit)
            )
            .disabled(!service.enabled || service.isCalibrating || service.accessState != .enabled)
            .opacity(service.enabled ? 1 : 0.45)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if service.accessState == .notRegistered {
            Button(strings.allowControl, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if service.accessState == .requiresApproval {
            Button(strings.openSettings, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if service.accessState == .enabled {
            Toggle(strings.enableToggle, isOn: Binding(
                get: { service.enabled },
                set: { service.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(service.isCalibrating)
            if service.enabled, canDischargeToLimit {
                Button(service.isDischargingToLimit ? strings.stopDischarge : strings.dischargeToLimit) {
                    if service.isDischargingToLimit { service.stopDischarge() }
                    else { service.startDischargeToLimit() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(service.isCalibrating || service.isWorking)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var calibrationBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.calibrationTitle).font(.system(size: 11, weight: .semibold))
            Text(strings.calibrationCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if service.isCalibrating {
                compactCalibration
                Button(strings.cancelCalibration, action: service.cancelCalibration)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else {
                Button(strings.startCalibration, action: service.startCalibration)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canStartCalibration || service.isWorking)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private var compactCalibration: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let phase = service.calibrationPhase {
                Text(phaseText(phase))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
            }
            if let remaining = service.holdRemainingSeconds {
                Text(String(format: strings.calHoldRemainingFormat,
                            max(1, Int((remaining / 60).rounded(.up)))))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if compact {
                Button(strings.cancelCalibration, action: service.cancelCalibration)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    private var canDischargeToLimit: Bool {
        service.profile?.supportsDischarge == true && (service.chargePercent ?? 0) > service.limitPercent
    }

    private var canStartCalibration: Bool {
        service.accessState == .enabled
            && service.profile?.supportsDischarge == true
            && service.externalConnected
            && !service.isDischargingToLimit
    }

    private var headerSymbol: String {
        if service.isDischargingToLimit || service.appliedGate == .forceDischarge { return "battery.25" }
        if service.isCharging { return "battery.100.bolt" }
        return "battery.75percent"
    }

    private var statusText: String {
        if service.isCalibrating, let phase = service.calibrationPhase { return phaseText(phase) }
        if service.isDischargingToLimit { return strings.discharging }
        if !service.externalConnected { return strings.onBattery }
        if service.appliedGate == .inhibitCharging { return strings.holding }
        if service.isCharging { return strings.charging }
        return strings.notCharging
    }

    private var statusColor: Color {
        if service.appliedGate == .forceDischarge || service.isDischargingToLimit {
            return ChargeLimitPalette.discharge(for: colorScheme)
        }
        if service.appliedGate == .inhibitCharging { return ChargeLimitPalette.lime(for: colorScheme) }
        if service.isCharging { return ChargeLimitPalette.charging(for: colorScheme) }
        return .secondary
    }

    private var stateMessage: String? {
        if !service.hasBattery { return strings.noBattery }
        if service.error == .unsupportedHardware { return strings.unsupported }
        switch service.error {
        case .helperUnavailable, .controlFailed: return strings.failed
        case .authorizationRequired: return strings.approvalCaption
        default: break
        }
        if service.accessState == .notRegistered || service.accessState == .requiresApproval {
            return strings.approvalCaption
        }
        if service.accessState == .enabled, service.profile?.supportsDischarge == false {
            return strings.calUnsupportedDischarge
        }
        return nil
    }

    private var messageIsError: Bool {
        switch service.error {
        case .helperUnavailable, .controlFailed, .unsupportedHardware: return true
        default: return false
        }
    }

    private func phaseText(_ phase: ChargeCalibrationPhase) -> String {
        switch phase {
        case .chargingToFull: return strings.calPhaseCharge
        case .dischargingToFloor: return strings.calPhaseDischarge
        case .chargingToFullAgain: return strings.calPhaseChargeAgain
        case .holdingAtFull: return strings.calPhaseHold
        case .restoringLimit: return strings.calPhaseRestore
        }
    }
}

private enum ChargeLimitPalette {
    static func lime(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.42, green: 0.52, blue: 0.02)
                         : Color(red: 0.80, green: 0.88, blue: 0.22)
    }
    static func charging(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.10, green: 0.55, blue: 0.28)
                         : Color(red: 0.55, green: 0.90, blue: 0.45)
    }
    static func discharge(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.72, green: 0.38, blue: 0.04)
                         : Color(red: 1.00, green: 0.68, blue: 0.22)
    }
    static func track(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10)
    }
}

struct ChargeLimitDial: View {
    let charge: Double
    let limit: Double
    let statusColor: Color
    let chargeLabel: String
    let statusLabel: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle().fill(colorScheme == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.035))
            ChargeLimitRing(progress: 1, lineWidth: 11)
                .foregroundStyle(ChargeLimitPalette.track(for: colorScheme))
            ChargeLimitRing(progress: min(max(charge, 0), 1), lineWidth: 11)
                .foregroundStyle(statusColor)
                .shadow(color: statusColor.opacity(0.35), radius: 6)
            ChargeLimitTick(progress: min(max(limit, 0), 1), lineWidth: 11)
                .stroke(Color.primary.opacity(0.92), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            VStack(spacing: 2) {
                Text(chargeLabel)
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                Text("%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .offset(y: -4)
                Text(statusLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .offset(y: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusLabel)
        .accessibilityValue("\(chargeLabel)%")
    }
}

private struct ChargeLimitRing: Shape {
    var progress: Double
    var lineWidth: CGFloat
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let radius = min(rect.width, rect.height) / 2 - inset
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(max(progress, 0), 1)), clockwise: false)
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

private struct ChargeLimitTick: Shape {
    var progress: Double
    var lineWidth: CGFloat
    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let radius = min(rect.width, rect.height) / 2 - inset
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = Angle.degrees(-90 + 360 * min(max(progress, 0), 1)).radians
        var path = Path()
        path.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * (radius - 7),
                              y: center.y + CGFloat(sin(angle)) * (radius - 7)))
        path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * (radius + 7),
                                 y: center.y + CGFloat(sin(angle)) * (radius + 7)))
        return path
    }
}

struct ChargeLimitSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = max(7, min(width - 7, width * fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(ChargeLimitPalette.track(for: colorScheme)).frame(height: 8)
                Capsule().fill(ChargeLimitPalette.lime(for: colorScheme)).frame(width: x, height: 8)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .overlay(Circle().strokeBorder(ChargeLimitPalette.lime(for: colorScheme).opacity(0.85), lineWidth: 2))
                    .offset(x: x - 9)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled else { return }
                let raw = min(max(drag.location.x / max(width, 1), 0), 1)
                let stepped = (range.lowerBound + raw * (range.upperBound - range.lowerBound)).rounded()
                value = min(max(stepped, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 22)
        .accessibilityValue("\(Int(value.rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            default: break
            }
        }
    }
}
