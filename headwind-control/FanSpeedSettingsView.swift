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
                }
            } footer: {
                Text("The default fan speed when a Headwind is connected.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fan Speed on Connect")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FanSpeedSettingsView()
    }
}
