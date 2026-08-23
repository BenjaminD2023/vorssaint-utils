// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Discovers the charging-control SMC keys this Mac actually exposes and writes
/// only those keys. Apple Silicon generations differ (CH0B/CH0C vs CHTE, CH0I
/// vs CHIE); Intel uses BCLM plus optional ACEN for a forced discharge.
final class ChargeControlHardware {
    private struct ChargePath {
        let family: ChargeControlFamily
        let enable: [(key: SMCClient.Key, bytes: [UInt8])]
        let inhibit: [(key: SMCClient.Key, bytes: [UInt8])]
    }

    private struct DischargePath {
        let on: [(key: SMCClient.Key, bytes: [UInt8])]
        let off: [(key: SMCClient.Key, bytes: [UInt8])]
    }

    private let client: SMCClient
    private let chargePath: ChargePath
    private let dischargePath: DischargePath?
    private let bclm: SMCClient.Key?
    let profile: ChargeControlHardwareProfile

    init?() {
        guard let client = SMCClient() else { return nil }
        self.client = client

        let ch0b = Self.byteKey("CH0B", in: client)
        let ch0c = Self.byteKey("CH0C", in: client)
        let chte = Self.ui32Key("CHTE", in: client)
        let ch0i = Self.byteKey("CH0I", in: client)
        let ch0j = Self.byteKey("CH0J", in: client)
        let chie = Self.byteKey("CHIE", in: client)
        let bclmKey = Self.byteKey("BCLM", in: client)
        let acen = Self.byteKey("ACEN", in: client)
        self.bclm = bclmKey

        if let bclmKey {
            chargePath = ChargePath(family: .intelBCLM, enable: [], inhibit: [])
            if let acen {
                dischargePath = DischargePath(on: [(acen, [0x00])], off: [(acen, [0x01])])
            } else {
                dischargePath = nil
            }
            _ = (ch0b, ch0c, chte, ch0i, ch0j, chie)
        } else if let chte {
            chargePath = ChargePath(
                family: .appleSiliconCHT,
                enable: [(chte, [0x00, 0x00, 0x00, 0x00])],
                inhibit: [(chte, [0x01, 0x00, 0x00, 0x00])])
            dischargePath = Self.appleSiliconDischarge(ch0i: ch0i, ch0j: ch0j, chie: chie)
            _ = (ch0b, ch0c)
        } else if ch0b != nil || ch0c != nil {
            var enable: [(key: SMCClient.Key, bytes: [UInt8])] = []
            var inhibit: [(key: SMCClient.Key, bytes: [UInt8])] = []
            if let ch0b {
                enable.append((ch0b, [0x00]))
                inhibit.append((ch0b, [0x02]))
            }
            if let ch0c {
                enable.append((ch0c, [0x00]))
                inhibit.append((ch0c, [0x02]))
            }
            chargePath = ChargePath(family: .appleSiliconCH0, enable: enable, inhibit: inhibit)
            dischargePath = Self.appleSiliconDischarge(ch0i: ch0i, ch0j: ch0j, chie: chie)
        } else {
            return nil
        }

        profile = ChargeControlHardwareProfile(
            family: chargePath.family,
            supportsInhibit: true,
            supportsDischarge: dischargePath != nil)
    }

    func apply(gate: ChargeControlGate, limit: Int) -> Bool {
        let cap = ChargeControlPolicy.sanitizedLimit(limit)
        switch gate {
        case .allowCharging:
            return setDischarge(false) && setChargingEnabled(true, limit: cap)
        case .inhibitCharging:
            return setDischarge(false) && setChargingEnabled(false, limit: cap)
        case .forceDischarge:
            guard profile.supportsDischarge else { return false }
            return setChargingEnabled(false, limit: cap) && setDischarge(true)
        }
    }

    func restoreNormal() -> Bool {
        setDischarge(false) && setChargingEnabled(true, limit: ChargeControlPolicy.maximumLimit)
    }

    var isForceDischarging: Bool {
        guard let dischargePath else { return false }
        return dischargePath.on.contains { pair in
            client.readBytes(pair.key) == pair.bytes
        }
    }

    private func setChargingEnabled(_ enabled: Bool, limit: Int) -> Bool {
        if let bclm {
            let value = UInt8(enabled ? ChargeControlPolicy.maximumLimit : limit)
            return write(bclm, bytes: [value])
        }
        let pairs = enabled ? chargePath.enable : chargePath.inhibit
        return writeAll(pairs)
    }

    private func setDischarge(_ enabled: Bool) -> Bool {
        guard let dischargePath else { return !enabled }
        return writeAll(enabled ? dischargePath.on : dischargePath.off)
    }

    private func writeAll(_ pairs: [(key: SMCClient.Key, bytes: [UInt8])]) -> Bool {
        guard !pairs.isEmpty else { return true }
        var anySucceeded = false
        for pair in pairs {
            if write(pair.key, bytes: pair.bytes) { anySucceeded = true }
        }
        return anySucceeded
    }

    private func write(_ key: SMCClient.Key, bytes: [UInt8], attempts: Int = 3) -> Bool {
        for attempt in 0..<attempts {
            do {
                try client.writeBytes(bytes, to: key)
                if client.readBytes(key) == bytes { return true }
                if attempt == attempts - 1 { return true }
            } catch {
                if attempt + 1 == attempts { return false }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private static func appleSiliconDischarge(ch0i: SMCClient.Key?,
                                              ch0j: SMCClient.Key?,
                                              chie: SMCClient.Key?) -> DischargePath? {
        var on: [(key: SMCClient.Key, bytes: [UInt8])] = []
        var off: [(key: SMCClient.Key, bytes: [UInt8])] = []
        if let ch0i {
            on.append((ch0i, [0x01]))
            off.append((ch0i, [0x00]))
        }
        if let ch0j {
            on.append((ch0j, [0x01]))
            off.append((ch0j, [0x00]))
        }
        if let chie {
            on.append((chie, [0x08]))
            off.append((chie, [0x00]))
        }
        guard !on.isEmpty else { return nil }
        return DischargePath(on: on, off: off)
    }

    private static func byteKey(_ name: String, in client: SMCClient) -> SMCClient.Key? {
        guard let key = client.key(named: name), key.dataSize == 1 else { return nil }
        return key
    }

    private static func ui32Key(_ name: String, in client: SMCClient) -> SMCClient.Key? {
        guard let key = client.key(named: name), key.dataSize == 4 else { return nil }
        return key
    }
}
