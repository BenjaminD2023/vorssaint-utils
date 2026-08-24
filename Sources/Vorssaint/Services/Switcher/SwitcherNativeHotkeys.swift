// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Turns Dock's ⌘Tab / ⌘⇧Tab / ⌘` hotkeys off while the App Switcher owns
/// those combinations, and puts back only the ones this process switched off.
/// The enabled state persists after quit, so every teardown path has to restore.
enum SwitcherNativeHotkeys {
    private static let lock = NSLock()
    private static var suppressed: Set<SwitcherNativeSymbolicHotKey> = []

    private typealias SetEnabledFunction = @convention(c) (Int32, Bool) -> CGError
    private static let setEnabled: SetEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetEnabledFunction.self)
    }()

    static func apply(_ desired: Set<SwitcherNativeSymbolicHotKey>) {
        lock.lock()
        defer { lock.unlock() }
        guard let setEnabled else { return }
        let transition = SwitcherSupport.nativeHotkeyTransition(from: suppressed, to: desired)
        var next = suppressed
        for key in transition.suppress where setEnabled(key.rawValue, false) == .success {
            next.insert(key)
        }
        for key in transition.restore where setEnabled(key.rawValue, true) == .success {
            next.remove(key)
        }
        suppressed = next
    }
}
