// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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

/// Compact limit slider under the Battery metric's charge percentage.
struct ChargeLimitInlineAdjuster: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @Environment(\.colorScheme) private var colorScheme

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        let _ = features.revision
        if PowerSampler.hasInternalBattery {
            VStack(alignment: .leading, spacing: 8) {
                Divider().opacity(0.55)

                HStack(spacing: 8) {
                    Text(strings.limitLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("\(service.limitPercent)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
                }

                ChargeLimitSlider(
                    value: Binding(
                        get: { Double(service.limitPercent) },
                        set: { applyLimit(Int($0.rounded())) }
                    ),
                    range: Double(ChargeControlPolicy.minimumLimit)...Double(ChargeControlPolicy.maximumLimit)
                )
                .disabled(service.isCalibrating)
                .opacity(service.isCalibrating ? 0.45 : 1)
                .help(strings.enableCaption)
                .accessibilityLabel(strings.limitLabel)

                footer
            }
            .onAppear { service.panelDidAppear() }
            .onDisappear { service.panelDidDisappear() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if service.accessState == .enabled {
            HStack(spacing: 8) {
                Toggle(strings.enableToggle, isOn: Binding(
                    get: { service.enabled },
                    set: { newValue in
                        ensureFeatureAvailable()
                        service.setEnabled(newValue)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(service.isCalibrating)
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        } else if service.accessState == .requiresApproval {
            Button(strings.openSettings, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            Text(strings.approvalCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button(strings.allowControl) {
                ensureFeatureAvailable()
                service.authorize()
            }
            .buttonStyle(.borderedProminent)
            .tint(ChargeLimitPalette.lime(for: colorScheme))
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            if let message = errorMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(strings.approvalCaption)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: String {
        if service.isCalibrating, let phase = service.calibrationPhase {
            switch phase {
            case .chargingToFull: return strings.calPhaseCharge
            case .dischargingToFloor: return strings.calPhaseDischarge
            case .chargingToFullAgain: return strings.calPhaseChargeAgain
            case .holdingAtFull: return strings.calPhaseHold
            case .restoringLimit: return strings.calPhaseRestore
            }
        }
        if service.isDischargingToLimit { return strings.discharging }
        if service.isToppingUp { return strings.toppingUp }
        if service.appliedGate == .inhibitCharging { return strings.holding }
        if service.isCharging { return strings.charging }
        if !service.externalConnected { return strings.onBattery }
        return strings.notCharging
    }

    private var statusColor: Color {
        if service.appliedGate == .forceDischarge || service.isDischargingToLimit {
            return ChargeLimitPalette.discharge(for: colorScheme)
        }
        if service.isToppingUp || service.isCharging {
            return ChargeLimitPalette.charging(for: colorScheme)
        }
        if service.appliedGate == .inhibitCharging {
            return ChargeLimitPalette.lime(for: colorScheme)
        }
        return .secondary
    }

    private var errorMessage: String? {
        switch service.error {
        case .unsupportedHardware: return strings.unsupported
        case .helperUnavailable, .controlFailed: return strings.failed
        default: return nil
        }
    }

    private func applyLimit(_ percent: Int) {
        ensureFeatureAvailable()
        if !service.enabled { service.setEnabled(true) }
        service.setLimit(percent)
    }

    private func ensureFeatureAvailable() {
        if !AppFeature.chargeControl.isAvailable {
            FeatureRuntime.shared.setAvailable(.chargeControl, true)
            service.panelDidAppear()
        }
    }
}

/// Discharge and Top up while the adapter is connected. Discharge drains to
/// the saved limit; Top up temporarily charges to 100% and then restores it.
struct ChargeLimitPowerActions: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    @Environment(\.colorScheme) private var colorScheme

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        Group {
            if service.accessState == .enabled,
               service.enabled,
               service.externalConnected,
               !service.isCalibrating,
               showDischarge || showTopUp {
                HStack(spacing: 8) {
                    if showDischarge {
                        Button(service.isDischargingToLimit ? strings.stopDischarge : strings.discharge) {
                            if service.isDischargingToLimit { service.stopDischarge() }
                            else { service.startDischargeToLimit() }
                        }
                        .buttonStyle(.bordered)
                        .tint(service.isDischargingToLimit
                              ? ChargeLimitPalette.discharge(for: colorScheme)
                              : nil)
                        .controlSize(.small)
                        .disabled(service.isWorking)
                        .frame(maxWidth: .infinity)
                    }
                    if showTopUp {
                        Button(service.isToppingUp ? strings.stopTopUp : strings.topUp) {
                            if service.isToppingUp { service.stopTopUp() }
                            else { service.startTopUp() }
                        }
                        .buttonStyle(.bordered)
                        .tint(service.isToppingUp
                              ? ChargeLimitPalette.charging(for: colorScheme)
                              : nil)
                        .controlSize(.small)
                        .disabled(service.isWorking)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear { service.panelDidAppear() }
    }

    private var showDischarge: Bool {
        service.profile?.supportsDischarge == true
            && ((service.chargePercent ?? 0) > service.limitPercent || service.isDischargingToLimit)
    }

    private var showTopUp: Bool {
        (service.limitPercent < ChargeControlPolicy.maximumLimit
            && (service.chargePercent ?? 0) < ChargeControlPolicy.maximumLimit)
            || service.isToppingUp
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
                value: Binding(
                    get: { Double(service.limitPercent) },
                    set: { newValue in
                        if !service.enabled { service.setEnabled(true) }
                        service.setLimit(Int(newValue.rounded()))
                    }
                ),
                range: Double(ChargeControlPolicy.minimumLimit)...Double(ChargeControlPolicy.maximumLimit)
            )
            .disabled(service.isCalibrating)
            .opacity(service.isCalibrating ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if service.accessState == .enabled {
            Toggle(strings.enableToggle, isOn: Binding(
                get: { service.enabled },
                set: { service.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(service.isCalibrating)
            if service.enabled {
                ChargeLimitPowerActions()
            }
        } else if service.accessState == .requiresApproval {
            Button(strings.openSettings, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else {
            Button(strings.allowControl, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
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

    private var canStartCalibration: Bool {
        service.accessState == .enabled
            && service.profile?.supportsDischarge == true
            && service.externalConnected
            && !service.isDischargingToLimit
    }

    private var headerSymbol: String {
        if service.isDischargingToLimit || service.appliedGate == .forceDischarge { return "battery.25" }
        if service.isCharging || service.isToppingUp { return "battery.100.bolt" }
        return "battery.75percent"
    }

    private var statusText: String {
        if service.isCalibrating, let phase = service.calibrationPhase { return phaseText(phase) }
        if service.isDischargingToLimit { return strings.discharging }
        if service.isToppingUp { return strings.toppingUp }
        if !service.externalConnected { return strings.onBattery }
        if service.appliedGate == .inhibitCharging { return strings.holding }
        if service.isCharging { return strings.charging }
        return strings.notCharging
    }

    private var statusColor: Color {
        if service.appliedGate == .forceDischarge || service.isDischargingToLimit {
            return ChargeLimitPalette.discharge(for: colorScheme)
        }
        if service.isToppingUp || service.isCharging {
            return ChargeLimitPalette.charging(for: colorScheme)
        }
        if service.appliedGate == .inhibitCharging { return ChargeLimitPalette.lime(for: colorScheme) }
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
            let width = max(geo.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
        .frame(height: 22)
        .overlay {
            ChargeLimitSliderCatcher(value: $value, range: range, isEnabled: isEnabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(value.rounded()))%")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            default: break
            }
        }
    }
}

/// AppKit mouse tracking so the knob still moves inside Settings' Form and
/// the panel's NSScrollView, which swallow SwiftUI DragGesture.
private struct ChargeLimitSliderCatcher: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        context.coordinator.bind(view, value: $value)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        context.coordinator.bind(view, value: $value)
        view.range = range
        view.isEnabled = isEnabled
        view.lastSent = value
    }

    final class Coordinator {
        func bind(_ view: CatcherView, value: Binding<Double>) {
            view.onChange = { value.wrappedValue = $0 }
        }
    }

    final class CatcherView: NSView {
        var range: ClosedRange<Double> = 20...100
        var isEnabled = true
        var lastSent: Double = 0
        var onChange: (Double) -> Void = { _ in }

        override var isOpaque: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }
        override func resetCursorRects() {
            guard isEnabled else { return }
            addCursorRect(bounds, cursor: .pointingHand)
        }
        override func mouseDown(with event: NSEvent) { send(event) }
        override func mouseDragged(with event: NSEvent) { send(event) }

        private func send(_ event: NSEvent) {
            guard isEnabled, bounds.width > 1 else { return }
            let x = convert(event.locationInWindow, from: nil).x
            let fraction = min(max(x / bounds.width, 0), 1)
            let next = (range.lowerBound + fraction * (range.upperBound - range.lowerBound)).rounded()
            let clamped = min(max(next, range.lowerBound), range.upperBound)
            guard clamped != lastSent else { return }
            lastSent = clamped
            onChange(clamped)
        }
    }
}
