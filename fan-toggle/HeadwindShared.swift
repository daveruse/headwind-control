//
//  HeadwindShared.swift
//  fan-toggle
//
//  Created by Dave Ruse on 8/20/26.
//

import Foundation

/// App Group bridge between the Control Center widget extension and the main app —
/// they're separate compiled targets/processes, so this file is duplicated (not shared)
/// from the headwind-control target. Keep both copies in sync.
enum HeadwindShared {
    static let appGroupID = "group.wahoo.headwind-control"
    static let peripheralIDKey = "HeadwindShared.peripheralID"
    static let isOnKey = "HeadwindShared.isOn"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
