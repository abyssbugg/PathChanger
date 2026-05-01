//
//  JoystickControlView.swift
//  PathChanger
//
//  Modern Pro UI - Gaming-style joystick control
//

import SwiftUI

struct JoystickControlView: View {
    @EnvironmentObject var appState: AppState
    @State private var knobPosition: CGPoint = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private let outerRadius: CGFloat = 60
    private let innerRadius: CGFloat = 25

    var body: some View {
        FloatingControlPanel(title: "Joystick", icon: "gamecontroller.fill") {
            VStack(spacing: 16) {
                // Joystick Area
                ZStack {
                    // Base
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.2), Color.black.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )

                    // Direction Indicators
                    ForEach(0..<4) { directionIndex in
                        Image(systemName: "triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.5))
                            .rotationEffect(.degrees(Double(directionIndex) * 90))
                            .offset(y: -outerRadius + 10)
                            .rotationEffect(.degrees(Double(directionIndex) * 90))
                    }

                    // Knob
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color.gray.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 0.5)
                        )
                        .offset(x: knobPosition.x + dragOffset.width, y: knobPosition.y + dragOffset.height)
                        .gesture(
                            DragGesture()
                                .updating($dragOffset) { value, state, _ in
                                    let maxOffset = outerRadius - innerRadius
                                    let rawX = value.translation.width
                                    let rawY = value.translation.height

                                    // Clamp to circular boundary
                                    let distance = sqrt(rawX * rawX + rawY * rawY)
                                    let clampedDistance = min(distance, maxOffset)
                                    let angle = atan2(rawY, rawX)
                                    let knobX = clampedDistance * cos(angle)
                                    let knobY = clampedDistance * sin(angle)
                                    state = CGSize(width: knobX, height: knobY)

                                    // Normalize to unit circle (-1..1 range with magnitude <= 1)
                                    let normalizedX = knobX / maxOffset
                                    let normalizedY = -knobY / maxOffset // Invert Y for map coordinates
                                    appState.updateJoystickDirection(CGPoint(x: normalizedX, y: normalizedY))
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        knobPosition = .zero
                                    }
                                    appState.updateJoystickDirection(.zero)
                                }
                        )
                }
                .frame(width: 140, height: 140)

                // Instructions
                Text("Drag to move")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180)
        }
    }
}

#if DEBUG
struct JoystickControlView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.blue.opacity(0.2).ignoresSafeArea()
            JoystickControlView()
                .environmentObject(AppState())
        }
    }
}
#endif
