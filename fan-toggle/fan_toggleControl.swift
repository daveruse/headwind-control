//
//  fan_toggleControl.swift
//  fan-toggle
//
//  Created by Dave Ruse on 8/20/26.
//

import AppIntents
import SwiftUI
import WidgetKit

struct fan_toggleControl: ControlWidget {
    static let kind: String = "wahoo.headwind-control.fan-toggle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isOn in
            ControlWidgetToggle(
                "Headwind Fan",
                isOn: isOn,
                action: SetFanPowerIntent()
            ) { isOn in
                Label(isOn ? "On" : "Off", systemImage: "wind")
            }
        }
        .displayName("Headwind Fan")
        .description("Turns the Wahoo KICKR HEADWIND on at full speed, or off.")
    }
}

extension fan_toggleControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            HeadwindShared.defaults.bool(forKey: HeadwindShared.isOnKey)
        }
    }
}

struct SetFanPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Headwind Fan Power"

    @Parameter(title: "Fan is on")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let client = HeadwindFanClient()
        if value {
            try await client.send([[0x04, 0x04, 0x00, 0x00], [0x02, 100, 0x00, 0x00]])
        } else {
            try await client.send([[0x04, 0x01, 0x00, 0x00]])
        }
        HeadwindShared.defaults.set(value, forKey: HeadwindShared.isOnKey)
        return .result()
    }
}
