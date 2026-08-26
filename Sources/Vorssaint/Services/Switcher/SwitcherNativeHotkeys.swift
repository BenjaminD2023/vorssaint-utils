// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Turns Dock's ⌘Tab / ⌘⇧Tab / ⌘` hotkeys off while the App Switcher owns
/// those combinations, and puts back only the ones Vorssaint switched off.
/// Both the enabled state and our ownership survive a process exit.
enum SwitcherNativeHotkeys {
    private static let lock = NSLock()
    private static let storageKey = "switcherNativeHotkeysSuppressed"
    private static var suppressed: Set<SwitcherNativeSymbolicHotKey> = {
        let stored = UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? []
        return Set(stored.compactMap { value in
            guard let rawValue = Int32(exactly: value) else { return nil }
            return SwitcherNativeSymbolicHotKey(rawValue: rawValue)
        })
    }()

    private typealias SetEnabledFunction = @convention(c) (Int32, Bool) -> CGError
    private typealias IsEnabledFunction = @convention(c) (Int32) -> Bool
    private static let setEnabled: SetEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetEnabledFunction.self)
    }()
    private static let isEnabled: IsEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: IsEnabledFunction.self)
    }()

    static func apply(_ desired: Set<SwitcherNativeSymbolicHotKey>) {
        lock.lock()
        defer { lock.unlock() }
        guard let setEnabled, let isEnabled else { return }
        let currentlyEnabled = Set(SwitcherNativeSymbolicHotKey.allCases.filter { isEnabled($0.rawValue) })
        let transition = SwitcherSupport.nativeHotkeyTransition(from: suppressed,
                                                                to: desired,
                                                                currentlyEnabled: currentlyEnabled)
        var next = suppressed
        for key in transition.suppress {
            let newlyOwned = next.insert(key).inserted
            if newlyOwned { persist(next) }
            if setEnabled(key.rawValue, false) != .success, newlyOwned {
                next.remove(key)
                persist(next)
            }
        }
        for key in transition.restore where setEnabled(key.rawValue, true) == .success {
            next.remove(key)
            persist(next)
        }
        suppressed = next
    }

    private static func persist(_ keys: Set<SwitcherNativeSymbolicHotKey>) {
        if keys.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else {
            UserDefaults.standard.set(keys.map { Int($0.rawValue) }.sorted(), forKey: storageKey)
        }
    }
}
