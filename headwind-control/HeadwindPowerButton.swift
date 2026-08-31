//
//  HeadwindPowerButton.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import SwiftUI

/// Power toggle for the main screen, matching the Figma power-button designs:
/// off / not-yet-connected (white thumb, no icon), connected + on (blue thumb,
/// white power icon, glowing LED), and connected + off (white thumb, dim power
/// icon, unlit LED). The thumb can be dragged between positions once connected,
/// snapping to whichever end it's closer to on release.
///
/// Sized at roughly 62% of the Figma frame (which gave the control the whole
/// screen) so it reads as a hero control without crowding out the other
/// controls already stacked below it in ContentView.
struct HeadwindPowerButton: View {
    let connectionState: HeadwindBLEManager.ConnectionState
    let isOn: Bool
    let onToggle: (Bool) -> Void

    private static let trackWidth: CGFloat = 105   // 84 × 1.5
    private static let trackHeight: CGFloat = 212  // 170 × 1.5
    private static let thumbDiameter: CGFloat = 100
    private static let thumbInset: CGFloat = 4.5   // 3 × 1.5
    private static let dotDiameter: CGFloat = 14
    private static let trackToDotSpacing: CGFloat = 22
    private static let iconSize: CGFloat = 42

    private static let trackBackground = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    private static let glowColor = Color(red: 0x27 / 255, green: 0xBA / 255, blue: 0xF0 / 255)
    private static let thumbOnFill = Color(red: 0x00 / 255, green: 0x7B / 255, blue: 0xC3 / 255)
    private static let thumbOnRing = [
        Color(red: 0x00 / 255, green: 0x85 / 255, blue: 0xD3 / 255),
        Color(red: 0x00 / 255, green: 0x82 / 255, blue: 0xCE / 255),
    ]
    private static let thumbOffFill = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)
    private static let thumbOffRing = [Color(red: 0xEE / 255, green: 0xEE / 255, blue: 0xEE / 255), .white]
    private static let iconOffColor = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
    private static let dotOnColor = Color(red: 0x27 / 255, green: 0xBA / 255, blue: 0xF0 / 255)

    /// Live finger position while a drag is in progress; nil when not dragging.
    @State private var dragY: CGFloat?
    /// Optimistic target set the moment a drag/tap ends, since `onToggle` writes to the
    /// fan over BLE and `isOn` only updates once that confirms. Cleared once `isOn` catches
    /// up, so the thumb settles into place immediately instead of snapping back and forth.
    @State private var pendingIsOn: Bool?

    private var isConnected: Bool { connectionState == .connected }
    private var effectiveIsOn: Bool { pendingIsOn ?? isOn }
    private var thumbOnTop: Bool { isConnected && effectiveIsOn }

    private var topY: CGFloat { Self.thumbInset }
    private var bottomY: CGFloat { Self.trackHeight - Self.thumbDiameter - Self.thumbInset }
    private var restY: CGFloat { thumbOnTop ? topY : bottomY }
    private var thumbY: CGFloat { dragY ?? restY }

    var body: some View {
        VStack(spacing: Self.trackToDotSpacing) {
            track
            dot
        }
        .opacity(isConnected ? 1 : 0.6)
        .onChange(of: isOn) { _, newValue in
            if pendingIsOn == newValue { pendingIsOn = nil }
        }
    }

    private var track: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Self.trackBackground)
                .shadow(color: Self.glowColor.opacity(thumbOnTop ? 0.35 : 0), radius: 10)

            thumb
                .offset(y: thumbY)
        }
        .frame(width: Self.trackWidth, height: Self.trackHeight)
        .animation(dragY == nil ? .spring(response: 0.45, dampingFraction: 0.75) : nil, value: thumbY)
        .contentShape(Capsule())
        .gesture(dragGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Power")
        .accessibilityValue(isConnected ? (effectiveIsOn ? "On" : "Off") : "Not connected")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isConnected else { return }
                dragY = min(max(restY + value.translation.height, topY), bottomY)
            }
            .onEnded { value in
                guard isConnected else { return }
                let shouldBeOn: Bool
                if abs(value.translation.height) < 10 {
                    // Barely moved — treat it as a tap rather than a drag.
                    shouldBeOn = !effectiveIsOn
                } else {
                    let midpoint = (topY + bottomY) / 2
                    shouldBeOn = (dragY ?? restY) < midpoint
                }
                dragY = nil
                if shouldBeOn != effectiveIsOn {
                    pendingIsOn = shouldBeOn
                    onToggle(shouldBeOn)
                }
            }
    }

    @ViewBuilder
    private var thumb: some View {
        ZStack {
            Circle()
                // Both branches are plain Color (not a Color/RadialGradient mix) so SwiftUI
                // can smoothly interpolate the fill during the on/off crossfade — mixing
                // ShapeStyle types via AnyShapeStyle has no defined interpolation and was
                // flashing black mid-transition instead of animating between the two colors.
                .fill(thumbOnTop ? Self.thumbOnFill : Self.thumbOffFill)
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: thumbOnTop ? Self.thumbOnRing : Self.thumbOffRing,
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 3
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            icon
        }
        .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
        .animation(.easeInOut(duration: 0.25), value: thumbOnTop)
    }

    @ViewBuilder
    private var icon: some View {
        if isConnected {
            Image(systemName: "power")
                .font(.system(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(effectiveIsOn ? .white : Self.iconOffColor)
                .transition(.opacity)
        }
    }

    private var dot: some View {
        Circle()
            .fill(thumbOnTop ? Self.glowColor : Self.dotOnColor)
            .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            .shadow(color: Self.glowColor.opacity(thumbOnTop ? 0.9 : 0), radius: thumbOnTop ? 6 : 0)
//            .scaleEffect(thumbOnTop ? 1 : 0.7)
            .opacity(isConnected ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: thumbOnTop)
            .animation(.easeOut(duration: 0.2), value: isConnected)
            .blur(radius: 3)
    }
}

#Preview("Not connected") {
    HeadwindPowerButton(connectionState: .scanning, isOn: false, onToggle: { _ in })
        .padding(60)
        .background(Color.black)
}

#Preview("Connected — On") {
    HeadwindPowerButton(connectionState: .connected, isOn: true, onToggle: { _ in })
        .padding(60)
        .background(Color.black)
}

#Preview("Connected — Off") {
    HeadwindPowerButton(connectionState: .connected, isOn: false, onToggle: { _ in })
        .padding(60)
        .background(Color.black)
}
