// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ChargeControlIdentifiers {
    static let teamID = "3D485NHW29"

    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.vorssaint.utils.dev"
    #else
    static let appBundleID = "com.vorssaint.utils"
    #endif

    static let helperID = "\(appBundleID).charge-control"
    static let plistName = "\(helperID).plist"

    static let appCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(appBundleID)\""
    static let helperCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(helperID)\""
}

@objc protocol ChargeControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func apply(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreNormal(withReply reply: @escaping (Data) -> Void)
}

enum ChargeControlIPC {
    static func encode(_ response: ChargeControlResponse) -> Data {
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"gate":"allowCharging","isDischarging":false},"error":"controlFailed"}"#.utf8)
    }

    static func decodeResponse(_ data: Data) -> ChargeControlResponse? {
        try? JSONDecoder().decode(ChargeControlResponse.self, from: data)
    }

    static func encode(_ request: ChargeControlRequest) -> Data {
        (try? JSONEncoder().encode(request))
            ?? Data(#"{"gate":"allowCharging","limitPercent":80}"#.utf8)
    }

    static func decodeRequest(_ data: Data) -> ChargeControlRequest? {
        try? JSONDecoder().decode(ChargeControlRequest.self, from: data)
    }
}
