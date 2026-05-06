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

    private let outerRadius: CGFloat = 76
    private let innerRadius: CGFloat = 24

    var body: some View {
        FloatingControlPanel(title: "Joystick Control", icon: "gamecontroller.fill") {
            VStack(spacing: AppSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Manual movement")
                            .font(AppFont.title)
                            .foregroundStyle(Color.pcText)
                        Text("Drag the control pad to stream direction updates")
                            .font(AppFont.metadata)
                            .foregroundStyle(Color.pcTextMuted)
                    }

                    Spacer()
                }
                ZStack {
                    Circle()
                        .fill(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.activeRow))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)

                    Circle()
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.divider), lineWidth: 1)
                        .frame(width: outerRadius * 1.45, height: outerRadius * 1.45)

                    Circle()
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.divider), lineWidth: 1)
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
                        .fill(Color.pcAccent)
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
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
            }
            .frame(width: 288)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }
}

#if DEBUG
struct JoystickControlView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.pcBackground.ignoresSafeArea()
            JoystickControlView()
                .environmentObject(AppState())
        }
    }
}
#endif
