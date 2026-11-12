//
//  ContentView.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import SwiftUI
import Vortex

struct ContentView: View {
    @StateObject private var ble = HeadwindBLEManager()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wind particle system. VortexSystem is a class, so mutating it here is picked up
    /// by the VortexView on its next frame without rebuilding the view.
    @State private var wind = VortexSystem.headwind
    /// Whether the VortexView is in the hierarchy. VortexView redraws every frame for as
    /// long as it's on screen, even with no particles, so it's removed once the wind
    /// stops and the last particles have faded out.
    @State private var showsWind = false
    @State private var windFadeOutTask: Task<Void, Never>?
    
    @State private var showingSettings = false

    private let presets: [(value: Int, assetName: String)] = [
        (25, "Percent25"),
        (50, "Percent50"),
        (75, "Percent75"),
        (100, "Max"),
    ]

    // Proportions measured from the Figma frame (393pt wide). The fan image is wider
    // than the screen and bleeds off the bottom edge.
    private let fanWidthRatio = 1.19
    private let fanBottomBleedRatio = 0.0
    /// Transparent space above the fan's top edge in the image, as a fraction of its height.
    private let fanImageTopInset = 0.105

    /// Vertical offset of the outer preset buttons relative to the middle two.
    private let outerPresetOffset: CGFloat = 35
    /// Gap between the lowest preset button and the top of the fan.
    private let presetToFanSpacing: CGFloat = 10
    private let logoHeight: CGFloat = 58
    /// Minimum height of the bottom control panel and its gradient.
    private let panelMinHeight: CGFloat = 200

    // Landscape proportions, relative to the full screen height.
    /// Fan image width as a multiple of the screen height.
    private let landscapeFanHeightRatio = 1.06
    /// How far the fan image extends below the bottom edge, as a fraction of its width.
    private let landscapeFanBottomBleedRatio = 0.084
    /// Top of the logo as a fraction of the screen height.
    private let landscapeLogoTopRatio = 0.26

    var body: some View {
        // Read the device's safe area outside the NavigationStack, so the toolbar
        // doesn't push the layout down. Everything below is positioned against the
        // full screen, keeping the logo and fan in fixed spots.
        GeometryReader { screen in
            NavigationStack {
                // A full-screen container that ignores the safe area (including the
                // toolbar). The fan and controls are overlays on it, so neither can
                // resize it: the fan stays pinned to the bottom edge, the logo stays put.
                Group {
                    if screen.size.width > screen.size.height {
                        landscapeLayout(screen)
                    } else {
                        portraitLayout(screen)
                    }
                }
                .background { background }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                ble.connect()
                updateWind()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // .onAppear only fires once per view lifecycle, so it misses the case
                // where the app is merely backgrounded (not relaunched) and reopened.
                if newPhase == .active {
                    ble.connect()
                }
            }
            .onChange(of: ble.connectionState) { updateWind() }
            .onChange(of: ble.targetSpeed) { updateWind() }
            .onChange(of: ble.isOn) { updateWind() }
            .onChange(of: reduceMotion) { updateWind() }
            // Status messages appear in place, so announce them for VoiceOver users
            // who aren't focused on the status area.
            .onChange(of: ble.statusText) { _, text in
                guard !text.isEmpty else { return }
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }

    // MARK: - Layouts

    /// Portrait: logo at the top, presets arched over the fan, controls along the bottom.
    private func portraitLayout(_ screen: GeometryProxy) -> some View {
        let fanWidth = screen.size.width * fanWidthRatio
        let visibleFanHeight = fanWidth * (1 - fanBottomBleedRatio - fanImageTopInset)
        let logoTop = screen.safeAreaInsets.top + 60
        // The outer buttons are offset down, which doesn't affect layout,
        // so include that offset when spacing the row above the fan.
        let presetRowBottom = visibleFanHeight + outerPresetOffset + presetToFanSpacing

        return Color.clear
            // The fan is wider than the screen; as an overlay its size doesn't
            // affect layout.
            .overlay(alignment: .bottom) {
                fanWithWind(width: fanWidth)
            }
            // Logo, presets, and status are anchored independently so that
            // changing content (e.g. a long status message) can't move the
            // logo or the preset row.
            .overlay(alignment: .top) {
                logo
                    .padding(.top, logoTop)
            }
            .overlay(alignment: .bottom) {
                presetControls
                    .padding(.bottom, presetRowBottom)
            }
            .overlay(alignment: .bottom) {
                controlPanel(bottomPadding: screen.safeAreaInsets.bottom + 26)
            }
    }

    /// Landscape: the fan and connect controls on the left half; the logo and presets
    /// on the right half. Proportions measured from the landscape Figma frame (852×393pt).
    private func landscapeLayout(_ screen: GeometryProxy) -> some View {
        let fullHeight = screen.size.height + screen.safeAreaInsets.top + screen.safeAreaInsets.bottom
        let fanWidth = fullHeight * landscapeFanHeightRatio

        // Layered so the gradient spans the full width (no seam at the middle) while
        // sitting above the fan and below the controls.
        return Color.clear
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                        .overlay(alignment: .bottom) {
                            fanWithWind(width: fanWidth)
                                .offset(y: fanWidth * landscapeFanBottomBleedRatio)
                        }
                    Color.clear
                }
            }
            .overlay(alignment: .bottom) {
                panelGradient
                    .frame(height: panelMinHeight)
            }
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                        .overlay(alignment: .bottom) {
                            controlPanel(
                                bottomPadding: screen.safeAreaInsets.bottom,
                                showsBackground: false,
                                // Keep longer statuses clear of the screen edge.
                                statusMaxWidth: 300
                            )
                        }
                    Color.clear
                        .overlay(alignment: .top) {
                            VStack(spacing: 24) {
                                logo
                                presetControls
                            }
                            .padding(.top, fullHeight * landscapeLogoTopRatio)
                            // Nudges the column toward the center, clear of the side safe area.
                            .padding(.trailing, 22)
                        }
                }
            }
    }

    // MARK: - Shared pieces

    private var logo: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 230, height: logoHeight)
            // Decorative branding; VoiceOver skips it.
            .accessibilityHidden(true)
    }

    private var presetControls: some View {
        presetRow
            // Attached to the row rather than each button: the buttons swap
            // between selected/unselected views, which would drop the modifier.
            .sensoryFeedback(.impact(weight: .medium), trigger: ble.targetSpeed)
    }

    /// Status and connect controls in a full-width panel, fading from dark up into the fan.
    /// Landscape draws the gradient separately across the full screen width.
    private func controlPanel(
        bottomPadding: CGFloat,
        showsBackground: Bool = true,
        statusMaxWidth: CGFloat = .infinity
    ) -> some View {
        VStack(spacing: 25) {
            connectButton
            // Reserve a fixed two-line area for the status so the panel's
            // height never changes, keeping the button in place whether
            // the status is empty, one line, or two.
            Text(verbatim: "\n")
                .font(.subheadline)
                .hidden()
                .accessibilityHidden(true)
                .frame(maxWidth: statusMaxWidth)
                .overlay(alignment: .top) {
                    statusHeader
                }
        }
        // Attached to the panel rather than the button, since the button
        // is replaced as soon as the connection state changes.
        .sensoryFeedback(trigger: ble.connectionState) { _, newState in
            switch newState {
            case .scanning, .connecting: .impact(weight: .light)
            case .connected: .success
            case .error: .error
            default: nil
            }
        }
        .padding(.horizontal)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, minHeight: panelMinHeight, alignment: .bottom)
        .background {
            if showsBackground {
                panelGradient
            }
        }
    }

    private var panelGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.97), location: 0.30),
                Gradient.Stop(color: Color(red: 0.2, green: 0.2, blue: 0.2).opacity(0), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.5, y: 1),
            endPoint: UnitPoint(x: 0.5, y: 0)
        )
    }

    private var background: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.2, green: 0.2, blue: 0.2), location: 0.0),
                Gradient.Stop(color: Color(red: 0.1, green: 0.1, blue: 0.1), location: 1.0),
            ],
            center: UnitPoint(x: 0.5, y: 0.8),
            endRadiusFraction: 0.75
        )
        .ignoresSafeArea()
    }

    /// The fan image with the wind particle layer extending one fan-height above it,
    /// so particles can travel up past the preset buttons.
    private func fanWithWind(width: CGFloat) -> some View {
        Image("HeadwindFanNoControls")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width)
            .overlay(alignment: .bottom) {
                if showsWind {
                    // 30 fps is visually indistinguishable for thin wind streaks and
                    // halves the per-frame particle update and drawing work.
                    VortexView(wind, targetFrameRate: 30) {
                        Circle()
                            .fill(.white)
                            .frame(width: 6, height: 6)
                            .blur(radius: 7)
                            .blendMode(.plusLighter)
                            .tag("streak")
                    }
                    .frame(width: width, height: width * 2)
                    .allowsHitTesting(false)
                }
            }
            .offset(y: width * fanBottomBleedRatio)
            .accessibilityHidden(true)
    }

    /// Testing override: show the wind effect even when no fan is connected.
    /// Set back to `false` to only show wind while the fan is running.
    private let alwaysShowWind = true

    /// Emits wind while the fan is running, with density and speed scaled by the fan speed.
    private func updateWind() {
        let level = Double(ble.targetSpeed) / 100
        // The wind is a large, continuous animation, so it's turned off entirely with
        // Reduce Motion. The highlighted preset still shows that the fan is running.
        let shouldEmit = !reduceMotion
            && (alwaysShowWind || (ble.connectionState == .connected && ble.isOn))
        wind.isActive = shouldEmit
        wind.birthRate = 30 + 120 * level
        wind.speed = 0.15 + 0.35 * level

        windFadeOutTask?.cancel()
        if shouldEmit {
            showsWind = true
        } else if showsWind {
            // Stop emitting now, but keep the view until the longest-lived particle
            // has died so the wind fades out rather than vanishing.
            let fadeOut = wind.lifespan + wind.lifespanVariation
            windFadeOutTask = Task {
                try? await Task.sleep(for: .seconds(fadeOut))
                guard !Task.isCancelled else { return }
                showsWind = false
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 22) {
            ForEach(Array(presets.enumerated()), id: \.element.value) { index, preset in
                presetButton(preset)
                    // Outer buttons sit lower, forming an arc over the fan.
                    .offset(y: index == 0 || index == presets.count - 1 ? outerPresetOffset : 0)
            }
        }
        .padding(.top, 25)
    }

    @ViewBuilder
    private var statusHeader: some View {
        Text(ble.statusText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    private func isSelected(_ value: Int) -> Bool {
        ble.connectionState == .connected && ble.isOn && ble.targetSpeed == value
    }

    private func presetButton(_ preset: (value: Int, assetName: String)) -> some View {
        let label = Image(preset.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 44, height: 44)
            .padding(6)
        let spokenName = preset.value == 100 ? "Maximum speed" : "\(preset.value) percent speed"
        let isConnected = ble.connectionState == .connected

        return Group {
            if isSelected(preset.value) {
                Button {
                    ble.applyPreset(preset.value)
                } label: {
                    label
                }
                .buttonStyle(.glassProminent)
            } else {
                Button {
                    ble.applyPreset(preset.value)
                } label: {
                    label
                }
                .buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.circle)
        .disabled(!isConnected)
        // The labels are images, so give VoiceOver a spoken name and selected state.
        .accessibilityLabel(spokenName)
        .accessibilityAddTraits(isSelected(preset.value) ? .isSelected : [])
        .accessibilityHint(isConnected ? "" : "Connect to your Headwind to change speed")
        // The image labels don't scale with Dynamic Type; at accessibility text sizes,
        // long-pressing shows an enlarged label instead.
        .accessibilityShowsLargeContentViewer {
            Text(preset.value == 100 ? "Max" : "\(preset.value)%")
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
        case .idle, .error, .poweredOff:
            Button {
                ble.connect()
            } label: {
                Label("Connect to Headwind", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            // Shown but unavailable until Bluetooth is turned back on.
            .disabled(ble.connectionState == .poweredOff)
        }
    }
}

extension VortexSystem {
    /// Wind blowing out of the fan's grill toward the viewer. Positions are in the unit
    /// space of a frame that is one fan-width wide and two fan-heights tall, aligned to
    /// the bottom of the fan image — so the grill spans x 0.35–0.66, y 0.58–0.78.
    static var headwind: VortexSystem {
        VortexSystem(
            tags: ["streak"],
            position: [0.5, 0.8],
            shape: .box(width: 0.2, height: 0.18),
            birthRate: 60,
            lifespan: 1.6,
            lifespanVariation: 0.4,
            speed: 0.3,
            speedVariation: 0.1,
            angleRange: .degrees(20),
            colors: .ramp(.white.opacity(0), .white.opacity(0.4), .white.opacity(0)),
            size: 0.2,
            sizeVariation: 0.3,
            sizeMultiplierAtDeath: 2.5,
            stretchFactor: 20
        )
    }
}

#Preview {
    ContentView()
}
