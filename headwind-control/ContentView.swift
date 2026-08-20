//
//  ContentView.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var ble = HeadwindBLEManager()
    @State private var sliderValue: Double = 50

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                statusHeader

                Toggle(isOn: Binding(
                    get: { ble.isOn },
                    set: { $0 ? ble.turnOn() : ble.turnOff() }
                )) {
                    Label("Power", systemImage: "power")
                        .font(.title3)
                }
                .toggleStyle(.switch)
                .disabled(ble.connectionState != .connected)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Speed: \(Int(sliderValue))%")
                        .font(.headline)
                    Slider(value: $sliderValue, in: 1...100, step: 1) { editing in
                        if !editing { ble.setSpeed(Int(sliderValue), debounce: false) }
                    }
                    .disabled(ble.connectionState != .connected)
                }

                HStack(spacing: 12) {
                    ForEach([25, 50, 75, 100], id: \.self) { preset in
                        Button("\(preset)%") {
                            sliderValue = Double(preset)
                            ble.applyPreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ble.connectionState != .connected)
                    }
                }

                Spacer()

                connectButton
            }
            .padding()
            .navigationTitle("Headwind")
            .onChange(of: ble.speed) { _, newValue in
                if newValue > 0 { sliderValue = Double(newValue) }
            }
            .onAppear { ble.connect() }
        }
    }

    @ViewBuilder
    private var statusHeader: some View {
        HStack {
            Image(systemName: ble.statusIcon)
                .foregroundStyle(statusColor)
            Text(ble.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if ble.connectionState == .scanning || ble.connectionState == .connecting {
                ProgressView()
            }
        }
    }

    private var statusColor: Color {
        switch ble.connectionState {
        case .connected: return ble.isOn ? .green : .primary
        case .connecting, .scanning: return .yellow
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
                Label("Disconnect", systemImage: "xmark.circle")
            }
        case .idle, .error:
            Button {
                ble.connect()
            } label: {
                Label("Connect", systemImage: "arrow.clockwise")
            }
        default:
            EmptyView()
        }
    }
}

#Preview {
    ContentView()
}
