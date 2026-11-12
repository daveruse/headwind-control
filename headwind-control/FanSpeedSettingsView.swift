//
//  FanSpeedSettingsView.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import SwiftUI

struct FanSpeedSettingsView: View {
    @AppStorage(AppSettings.defaultFanSpeedKey) private var defaultFanSpeed = 50
    @Environment(\.dismiss) private var dismiss

    private let options = [25, 50, 75, 100]

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.self) { option in
                    Button {
                        defaultFanSpeed = option
                        dismiss()
                    } label: {
                        HStack {
                            Text(AppSettings.fanSpeedLabel(option))
                                .foregroundStyle(.primary)
                            Spacer()
                            if option == defaultFanSpeed {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The checkmark is visual only; expose the selection to VoiceOver.
                    .accessibilityAddTraits(option == defaultFanSpeed ? .isSelected : [])
                }
            } footer: {
                Text("The fan speed that is set automatically when a Headwind is connected.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default Fan Speed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FanSpeedSettingsView()
    }
}
