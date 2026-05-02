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

    private let outerRadius: CGFloat = 84
    private let innerRadius: CGFloat = 28

    var body: some View {
        FloatingControlPanel(title: "Joystick Control", icon: "gamecontroller.fill") {
            VStack(spacing: AppSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Manual movement")
                            .font(AppFont.subheading)
                            .foregroundStyle(Color.pcText)
                        Text("Drag the control pad to stream direction updates")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(Color.pcTextMuted)
                    }

                    Spacer()

                    PCStatusChip(
                        title: appState.isSimulating ? "Active" : "Ready",
                        icon: "dot.radiowaves.left.and.right",
                        color: appState.isSimulating ? .pcSecondary : .pcPrimary
                    )
                }
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.pcAccent.opacity(0.18),
                                    Color.pcSurfaceHigh.opacity(0.72),
                                    Color.pcSurface.opacity(0.85)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: outerRadius
                            )
                        )
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(Color.pcAccent.opacity(0.22), lineWidth: 2)
                        )
                        .shadow(color: Color.pcAccent.opacity(0.12), radius: 18)

                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: outerRadius * 1.45, height: outerRadius * 1.45)

                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: outerRadius * 0.82, height: outerRadius * 0.82)

                    Text("N").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(y: -outerRadius + 13)
                    Text("S").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(y: outerRadius - 13)
                    Text("W").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(x: -outerRadius + 13)
                    Text("E").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(x: outerRadius - 13)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.pcPrimary, Color.pcAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .shadow(color: Color.pcAccent.opacity(0.45), radius: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 2)
                        )
                        .overlay(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
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
                .frame(width: outerRadius * 2, height: outerRadius * 2)

                Text("Drag to move")
                    .font(AppFont.monoSmall)
                    .foregroundStyle(Color.pcTextMuted)
                    .italic()
            }
            .frame(width: 300)
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
