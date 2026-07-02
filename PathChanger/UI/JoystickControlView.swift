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
    private let outerRadius: CGFloat = DS.Metrics.joystickOuterRadius
    private let innerRadius: CGFloat = DS.Metrics.joystickInnerRadius

    var body: some View {
        FloatingControlPanel(title: "Joystick Control", icon: "gamecontroller.fill") {
            // Operational refinement: collapse the redundant heading copy
            // (panel title already says "Joystick Control"), tighten vertical
            // chaining (sm vs md) and drop the dead "Drag to move" caption —
            // the N/S/E/W dial already conveys it. startLocationSummary
            // provides the empty-state hint when no start point is selected.
            VStack(spacing: AppSpacing.sm) {
                joystickPanelStateStrip
                startLocationSummary
                ZStack {
                    Circle()
                        .fill(Color.pcSurfaceHigh.opacity(joystickIsLive ? AppSurfaceAlpha.activeRow : AppSurfaceAlpha.idleRow))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
                        )
                        .shadow(
                            color: DS.Color.shadow.opacity(DS.Opacity.searchResultsShadow),
                            radius: DS.Metrics.mapSearchResultsShadowRadius,
                            y: DS.Metrics.mapSearchResultsShadowYOffset
                        )

                    Circle()
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.divider), lineWidth: DS.Metrics.strokeWidth)
                        .frame(
                            width: outerRadius * DS.Metrics.joystickOuterRingScale,
                            height: outerRadius * DS.Metrics.joystickOuterRingScale
                        )

                    Circle()
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.divider), lineWidth: DS.Metrics.strokeWidth)
                        .frame(
                            width: outerRadius * DS.Metrics.joystickInnerRingScale,
                            height: outerRadius * DS.Metrics.joystickInnerRingScale
                        )

                    Text("N").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(y: -outerRadius + DS.Metrics.joystickDirectionInset)
                    Text("S").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(y: outerRadius - DS.Metrics.joystickDirectionInset)
                    Text("W").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(x: -outerRadius + DS.Metrics.joystickDirectionInset)
                    Text("E").font(AppFont.monoSmall).foregroundStyle(Color.pcTextMuted)
                        .offset(x: outerRadius - DS.Metrics.joystickDirectionInset)

                    Circle()
                        .fill(joystickIsLive ? Color.pcAccent : Color.pcTextMuted)
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
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
                                    withAnimation(
                                        .spring(
                                            response: DS.Metrics.joystickReleaseSpringResponse,
                                            dampingFraction: DS.Metrics.joystickReleaseSpringDamping
                                        )
                                    ) {
                                        knobPosition = .zero
                                    }
                                    appState.updateJoystickDirection(.zero)
                                }
                        )

                    if !joystickIsLive {
                        VStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "pause.circle")
                                .font(AppFont.label)
                            Text("Preview only")
                                .font(AppFont.metadata)
                        }
                        .foregroundStyle(Color.pcTextMuted)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(Color.pcSurface.opacity(AppSurfaceAlpha.panel), in: Capsule())
                        .accessibilityHidden(true)
                    }
                }
                .frame(width: outerRadius * 2, height: outerRadius * 2)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(joystickIsLive)
                .accessibilityHint(joystickIsLive ? "Drag to stream joystick direction to the device." : "Start Joystick to send movement to the device.")
            }
            // Operational refinement: standardize panel width to align with
            // Teleport/Multi-Spot (312–332). The joystick dial now centers
            // horizontally inside the panel without dead horizontal padding.
            .frame(
                minWidth: DS.Metrics.mapTeleportPanelMinWidth,
                idealWidth: DS.Metrics.mapTeleportPanelIdealWidth,
                maxWidth: DS.Metrics.mapTeleportPanelMaxWidth
            )
        }
        .frame(maxWidth: DS.Metrics.mapTeleportPanelMaxWidth, alignment: .leading)
    }
    private var joystickIsLive: Bool {
        appState.isSimulating
    }

    private var joystickPanelStateStrip: some View {
        PanelStateStrip(
            title: joystickIsLive ? "Live" : "Not live",
            detail: joystickIsLive ? "Dragging moves the device" : "Start Joystick to send movement to the device.",
            icon: joystickIsLive ? "dot.radiowaves.left.and.right" : "pause.circle",
            color: joystickIsLive ? .pcSecondary : .pcTextMuted,
            accessibilityIdentifier: "joystickPanelStateStrip"
        )
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
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
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
