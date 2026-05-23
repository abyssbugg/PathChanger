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

    private let outerRadius: CGFloat = 56
    private let innerRadius: CGFloat = 18

    var body: some View {
        FloatingControlPanel(title: "Joystick Control", icon: "gamecontroller.fill") {
            // Operational refinement: collapse the redundant heading copy
            // (panel title already says "Joystick Control"), tighten vertical
            // chaining (sm vs md) and drop the dead "Drag to move" caption —
            // the N/S/E/W dial already conveys it. startLocationSummary
            // provides the empty-state hint when no start point is selected.
            VStack(spacing: AppSpacing.sm) {
                startLocationSummary
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
                            // W1 visual governance: joystick drag handling is a
                            // subordinate interaction that streams directional
                            // context; it is not a canonical T0 execution authority.
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
                .frame(maxWidth: .infinity)
            }
            // Operational refinement: standardize panel width to align with
            // Teleport/Multi-Spot (312–332). The joystick dial now centers
            // horizontally inside the panel without dead horizontal padding.
            .frame(minWidth: 280, idealWidth: 296, maxWidth: 312)
        }
        .frame(maxWidth: 312, alignment: .leading)
    }

    private var startLocationSummary: some View {
        let start = appState.currentLocation ?? appState.targetLocation
        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: "scope")
                .foregroundStyle(start == nil ? Color.pcTextMuted : Color.pcPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(appState.targetLocationName ?? "No start selected")
                    .font(AppFont.label)
                    .foregroundStyle(Color.pcText)
                    .lineLimit(1)
                Text(start?.formattedShort ?? "Use sidebar search or tap the map")
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
        .accessibilityIdentifier("joystickStartLocationSummary")
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
