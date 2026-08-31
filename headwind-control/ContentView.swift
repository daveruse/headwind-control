//
//  ContentView.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var ble = HeadwindBLEManager()
    @Environment(\.scenePhase) private var scenePhase

    private let presets: [(value: Int, assetName: String)] = [
        (25, "Percent25"),
        (50, "Percent50"),
        (75, "Percent75"),
        (100, "Max"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.2, green: 0.2, blue: 0.2), location: 0.20),
                        Gradient.Stop(color: Color(red: 0.1, green: 0.1, blue: 0.1), location: 1.00),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.5)
                )
                .preferredColorScheme(.dark)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 50)
                Spacer()
                HeadwindPowerButton(
                    connectionState: ble.connectionState,
                    isOn: ble.isOn,
                    onToggle: { $0 ? ble.turnOn() : ble.turnOff() }
                )
                //                .navigationBarItems(trailing: Image(systemName: "gearshape"))
                
                HStack(spacing: 10) {
                    Spacer()
                    ForEach(Array(presets.enumerated()), id: \.element.value) { index, preset in
                        presetButton(preset)
                            .padding(.top, index == 1 || index == 2 ? 00 : -80)
                    }
                    Spacer()

                }
                
                Spacer()
                
                statusHeader
                
                connectButton
                
                Spacer()
                
            }
            .padding()
            .navigationTitle("")
            .toolbar {
                            // Places the icon button on the top right
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView()
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
            .onAppear {
                ble.connect()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // .onAppear only fires once per view lifecycle, so it misses the case
                // where the app is merely backgrounded (not relaunched) and reopened.
                if newPhase == .active {
                    ble.connect()
                }
            }
        }
    }
        
    }

    @ViewBuilder
    private var statusHeader: some View {
        // The Connect button already communicates "connecting" (its own text + animated
        // icon), so there's nothing useful to show here while scanning/connecting. Stay
        // rendered (just invisible) rather than being omitted, so this row keeps reserving
        // its layout space instead of the rest of the UI shifting around it.
        HStack {
            Spacer()
            Image(systemName: ble.statusIcon)
                .foregroundStyle(statusColor)
            Text(ble.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .opacity(ble.connectionState == .scanning || ble.connectionState == .connecting ? 0 : 1)
    }

    private func isSelected(_ value: Int) -> Bool {
        ble.connectionState == .connected && ble.isOn && ble.targetSpeed == value
    }

    @ViewBuilder
    
    private func presetButton(_ preset: (value: Int, assetName: String)) -> some View {
        let label = Image(preset.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: 60)

        if isSelected(preset.value) {
            Button {
                ble.applyPreset(preset.value)
            } label: {
                label
            }
            .buttonStyle(.glassProminent)
            .disabled(ble.connectionState != .connected)
        } else {
            Button {
                ble.applyPreset(preset.value)
            } label: {
                label
            }
            .buttonStyle(.glass)
            .disabled(ble.connectionState != .connected)
        }
    }

    private var statusColor: Color {
        // .connecting/.scanning aren't handled here — statusHeader doesn't render at all
        // in those states (see above).
        switch ble.connectionState {
        case .connected: return ble.isOn ? .green : .primary
        case .error: return .red
        default: return .gray
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        switch ble.connectionState {
        case .connected:
            Button(role: .destructive) {
                ble.disconnect()
            } label: {
                Label("Disconnect", systemImage: "fan.slash")
            }
            .controlSize(.large)
            .buttonStyle(.glass)
        case .scanning, .connecting:
            Button {
                ble.connect()
            } label: {
                Label {
                    Text("Connecting")
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .symbolEffect(.variableColor.iterative.reversing, isActive: true)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        case .idle, .error:
            Button {
                ble.connect()
            } label: {
                Label("Connect to Headwind", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        default:
            EmptyView()
            .controlSize(.large)
        }
    }
}

#Preview {
    ContentView()
}
