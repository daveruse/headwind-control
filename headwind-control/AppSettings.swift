//
//  AppSettings.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import Foundation

/// UserDefaults keys for the Settings screen, shared by SettingsView,
/// FanSpeedSettingsView, ContentView, and HeadwindBLEManager.
enum AppSettings {
    static let autoPowerOnKey = "AppSettings.autoPowerOnEnabled"
    static let defaultFanSpeedKey = "AppSettings.defaultFanSpeedPercent"

    /// "25%", "50%", "75%", "Max" — matches the preset labels used elsewhere in the app.
    static func fanSpeedLabel(_ value: Int) -> String {
        value >= 100 ? "Max" : "\(value)%"
    }

    /// Reads the Auto Power On setting from UserDefaults directly (for HeadwindBLEManager,
    /// which isn't a View and can't use @AppStorage). `bool(forKey:)` defaults to `false`
    /// for an absent key, but this setting defaults to `true` until the user visits
    /// Settings, so an absent key is treated as enabled to match @AppStorage's default.
    static var isAutoPowerOnEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: autoPowerOnKey) == nil ? true : defaults.bool(forKey: autoPowerOnKey)
    }

    /// The persisted "Fan Speed on Connect" default, read fresh from UserDefaults (for
    /// HeadwindBLEManager, which isn't a View). Read directly at connect time rather than
    /// via HeadwindBLEManager.targetSpeed, which also tracks the fan's live reported speed
    /// via BLE notifications and would otherwise clobber a just-changed setting.
    static var defaultFanSpeed: Int {
        let saved = UserDefaults.standard.integer(forKey: defaultFanSpeedKey)
        return saved > 0 ? saved : 50
    }
}
