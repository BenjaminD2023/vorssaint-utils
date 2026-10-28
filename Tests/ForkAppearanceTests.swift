// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum ForkAppearanceTests {
    static func run(_ suite: TestSuite) {
        let registeredDefaults = Defaults.registeredDefaults
        suite.expect(registeredDefaults[DefaultsKey.menuBarCPUAppearance] as? String == ""
                && registeredDefaults[DefaultsKey.menuBarGPUAppearance] as? String == ""
                && registeredDefaults[DefaultsKey.menuBarMemoryAppearance] as? String == ""
                && registeredDefaults[DefaultsKey.menuBarDiskUsageAppearance] as? String == ""
                && registeredDefaults[DefaultsKey.menuBarBatteryAppearance] as? String == ""
                && registeredDefaults[DefaultsKey.menuBarPeripheralBatteryAppearance] as? String == "",
               "per-item menu bar appearances inherit the global choice until set")
        suite.expect(Defaults.sanitizedMenuBarMetricItemAppearance("") == "",
               "an empty per-item appearance stays empty so it can inherit")
        suite.expect(Defaults.sanitizedMenuBarMetricItemAppearance("bars") == "bars",
               "a per-item bar appearance is a valid stored choice")
        suite.expect(Defaults.sanitizedMenuBarMetricItemAppearance("banana") == "values",
               "unknown per-item appearances fall back to numeric values")
        suite.expect(MenuBarMetricAppearance.barCapableAppearanceKeys == [
            DefaultsKey.menuBarCPUAppearance,
            DefaultsKey.menuBarGPUAppearance,
            DefaultsKey.menuBarMemoryAppearance,
            DefaultsKey.menuBarDiskUsageAppearance,
            DefaultsKey.menuBarBatteryAppearance,
            DefaultsKey.menuBarPeripheralBatteryAppearance,
        ], "usage bars cover every percentage based menu bar metric")
        let appearanceSuite = "vorss.tests.menuBarAppearance"
        if let appearanceDefaults = UserDefaults(suiteName: appearanceSuite) {
            appearanceDefaults.removePersistentDomain(forName: appearanceSuite)
            appearanceDefaults.set("bars", forKey: DefaultsKey.menuBarMetricAppearance)
            suite.expect(MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarCPUAppearance,
                                                   in: appearanceDefaults) == .bars
                    && MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarGPUAppearance,
                                                       in: appearanceDefaults) == .bars
                    && MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarMemoryAppearance,
                                                       in: appearanceDefaults) == .bars
                    && MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarDiskUsageAppearance,
                                                       in: appearanceDefaults) == .bars
                    && MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarBatteryAppearance,
                                                       in: appearanceDefaults) == .bars
                    && MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarPeripheralBatteryAppearance,
                                                       in: appearanceDefaults) == .bars,
                   "an unset per-item appearance follows the global bars choice")
            appearanceDefaults.set("values", forKey: DefaultsKey.menuBarCPUAppearance)
            suite.expect(MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarCPUAppearance,
                                                   in: appearanceDefaults) == .values
                    && MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarGPUAppearance,
                                                       in: appearanceDefaults) == .bars
                    && MenuBarMetricAppearance.usesBars(appearanceKey: DefaultsKey.menuBarGPUAppearance,
                                                        in: appearanceDefaults)
                    && !MenuBarMetricAppearance.usesBars(appearanceKey: DefaultsKey.menuBarCPUAppearance,
                                                         in: appearanceDefaults),
                   "a per-item appearance overrides only that metric")
            suite.expect(MenuBarMetricAppearance.anyUsesBars(in: appearanceDefaults),
                   "any usage bar is enough to keep bar colors available")
            appearanceDefaults.set("values", forKey: DefaultsKey.menuBarMetricAppearance)
            appearanceDefaults.set("", forKey: DefaultsKey.menuBarCPUAppearance)
            appearanceDefaults.set("values", forKey: DefaultsKey.menuBarGPUAppearance)
            appearanceDefaults.set("values", forKey: DefaultsKey.menuBarMemoryAppearance)
            appearanceDefaults.set("values", forKey: DefaultsKey.menuBarDiskUsageAppearance)
            appearanceDefaults.set("values", forKey: DefaultsKey.menuBarBatteryAppearance)
            appearanceDefaults.set("values", forKey: DefaultsKey.menuBarPeripheralBatteryAppearance)
            suite.expect(!MenuBarMetricAppearance.anyUsesBars(in: appearanceDefaults),
                   "all-values usage metrics hide the bar color controls")
            appearanceDefaults.set("banana", forKey: DefaultsKey.menuBarCPUAppearance)
            suite.expect(MenuBarMetricAppearance.current(appearanceKey: DefaultsKey.menuBarCPUAppearance,
                                                   in: appearanceDefaults) == .values,
                   "a corrupt per-item appearance falls back to numeric values")
            appearanceDefaults.removePersistentDomain(forName: appearanceSuite)
        }
        suite.expect(MenuBarBatterySupport.symbolName(for: 75, isCharging: false) == "battery.75percent",
               "on battery the native fill matches the charge")
        suite.expect(MenuBarBatterySupport.symbolName(for: 40, isCharging: true, isPluggedIn: true)
                == "battery.100percent.bolt",
               "charging uses the native lightning battery")
        suite.expect(MenuBarBatterySupport.symbolName(for: 80, isCharging: false, isPluggedIn: true)
                == "powercord.fill",
               "plugged in without charging uses the power-cord state")
        suite.expect(MenuBarBatterySupport.symbolColor(lowPowerMode: true) == MenuBarBatterySupport.lowPowerColor
                && MenuBarBatterySupport.symbolColor(lowPowerMode: false) == MenuBarBatterySupport.valueColor,
               "Low Power Mode tints the native battery icon yellow")
        var lightBatteryText = NSColor.clear
        var darkBatteryText = NSColor.clear
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            lightBatteryText = MenuBarBatterySupport.valueColor.usingColorSpace(.sRGB) ?? .clear
        }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            darkBatteryText = MenuBarBatterySupport.valueColor.usingColorSpace(.sRGB) ?? .clear
        }
        suite.expect(lightBatteryText.redComponent < 0.1
                && darkBatteryText.redComponent > 0.9
                && lightBatteryText.alphaComponent == 1
                && darkBatteryText.alphaComponent == 1,
               "native battery text follows light and dark menu bar appearances")
        let nativeBatteryConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .labelColor))
        let nativeBatterySize = NSImage(systemSymbolName: "battery.100percent", accessibilityDescription: nil)?
            .withSymbolConfiguration(nativeBatteryConfiguration)?.size ?? CGSize(width: 31, height: 14)
        let batteryGlyphSize = MenuBarBatterySupport.glyphSize
        suite.expect(batteryGlyphSize.width.isFinite && batteryGlyphSize.height.isFinite
                && batteryGlyphSize.width > 0 && batteryGlyphSize.height > 0
                && batteryGlyphSize == nativeBatterySize,
               "menu bar battery matches the current native 18-point status-item symbol size: "
                + "actual \(batteryGlyphSize), expected \(nativeBatterySize)")
        suite.expect(MenuBarBatterySupport.glyphImage(percent: 63,
                                                isCharging: true,
                                                isPluggedIn: false,
                                                lowPowerMode: false).size
                == MenuBarBatterySupport.glyphSize,
               "charging battery composition preserves the native glyph size")
        let pluggedLowBattery = MenuBarBatterySupport.glyphImage(percent: 20,
                                                                 isCharging: false,
                                                                 isPluggedIn: true,
                                                                 lowPowerMode: false)
        let pluggedHighBattery = MenuBarBatterySupport.glyphImage(percent: 80,
                                                                  isCharging: false,
                                                                  isPluggedIn: true,
                                                                  lowPowerMode: false)
        suite.expect(pluggedLowBattery.tiffRepresentation != pluggedHighBattery.tiffRepresentation,
               "plugged battery glyph keeps tracking the live charge")
        let chargingHighBattery = MenuBarBatterySupport.glyphImage(percent: 80,
                                                                   isCharging: true,
                                                                   isPluggedIn: false,
                                                                   lowPowerMode: false)
        suite.expect(chargingHighBattery.tiffRepresentation != pluggedHighBattery.tiffRepresentation,
               "battery glyph reflects a charging-state change at the same level")
        for percent in [0, 20, 34, 35, 50, 74] {
            for tint in [NSColor.black, NSColor.white] {
                let glyph = MenuBarBatterySupport.glyphImage(percent: percent,
                                                              isCharging: true,
                                                              isPluggedIn: true,
                                                              lowPowerMode: false,
                                                              tint: tint)
                if let data = glyph.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: data) {
                    var foregroundPixels = 0
                    var wrongColorPixels = 0
                    for x in 0..<bitmap.pixelsWide {
                        for y in 0..<bitmap.pixelsHigh {
                            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                                  color.alphaComponent > 0.5 else { continue }
                            foregroundPixels += 1
                            if abs(color.redComponent - (tint == .black ? 0 : 1)) > 0.1 {
                                wrongColorPixels += 1
                            }
                        }
                    }
                    suite.expect(foregroundPixels > 0 && wrongColorPixels == 0,
                           "low-charge bolt uses the foreground tint at \(percent)% without a white-on-light bolt")
                } else {
                    suite.expect(false, "low-charge glyph can be rasterized")
                }
            }
        }
        suite.expectClose(Double(MenuBarBatterySupport.fillFraction(63)), 0.63,
                    "native battery fill follows the live charge")
        suite.expectClose(Double(MenuBarBatterySupport.fillFraction(150)), 1,
                    "native battery fill clamps above full")
        let batteryBounds = NSRect(origin: .zero, size: MenuBarBatterySupport.glyphSize)
        let fullBatteryWidth = MenuBarBatterySupport.fillRect(in: batteryBounds, percent: 100).width
        suite.expectClose(Double(MenuBarBatterySupport.fillRect(in: batteryBounds, percent: 13).width / fullBatteryWidth), 0.13,
                    "low battery fill stays linear")
        suite.expectClose(Double(MenuBarBatterySupport.fillRect(in: batteryBounds, percent: 90).width / fullBatteryWidth), 0.90,
                    "high battery fill stays linear")
        let unpluggedHighBattery = MenuBarBatterySupport.glyphImage(percent: 80,
                                                                    isCharging: false,
                                                                    isPluggedIn: false,
                                                                    lowPowerMode: false)
        suite.expect(pluggedHighBattery.tiffRepresentation != unpluggedHighBattery.tiffRepresentation,
               "plugged in without charging draws the plug inside the battery")
        suite.expectClose(MenuBarUsageBarSupport.percentFraction(80), 0.8,
                    "menu bar battery bars map a percent onto the 0...1 fill")
        suite.expectClose(MenuBarUsageBarSupport.percentFraction(150), 1,
                    "menu bar percent bars clamp readings above full")
    }
}
