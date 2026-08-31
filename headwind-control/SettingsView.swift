//
//  SettingsView.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.autoPowerOnKey) private var autoPowerOnEnabled = true
    @AppStorage(AppSettings.defaultFanSpeedKey) private var defaultFanSpeed = 50

    var body: some View {
        List {
            Section {
                Toggle(isOn: $autoPowerOnEnabled) {
                    Label {
                        Text("Enable Fan on Connect")
                    } icon: {
                        Image(systemName: "fan.badge.automatic.fill")
                            .foregroundStyle(.tint)
                    }
                }
            } footer: {
                Text("Automatically turn on your Headwind, at the configured speed, whenever it connects.")
            }

            Section {
                NavigationLink {
                    FanSpeedSettingsView()
                } label: {
                    Label {
                        HStack {
                            Text("Initial Fan Speed")
                            Spacer()
                            Text(AppSettings.fanSpeedLabel(defaultFanSpeed))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wind")
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
