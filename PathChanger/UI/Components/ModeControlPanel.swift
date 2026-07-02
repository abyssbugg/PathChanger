//
//  ModeControlPanel.swift
//  PathChanger
//
//  Right-hand control panel — the SwiftUI port of the mockup's `.panel`:
//  an accent mode tab strip (Teleport / Multi-Spot / Joystick) over per-mode
//  control cards, with the PrimaryActionPill docked full-width at the bottom.
//
//  Subordinate by design: the cards prepare target/route/joystick CONTEXT on
//  AppState (target selection, waypoint edits, joystick streaming). Execution
//  stays with PrimaryActionPill (SOLE production T0 execution authority).
//

import SwiftUI

struct ModeControlPanel: View {
    @Binding var selectedMode: AppMode
    @EnvironmentObject var appState: AppState

    @State private var latitudeInput: String = ""
    @State private var longitudeInput: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case latitude, longitude }

    /// Tabs shown in the strip (Settings is reached from the sidebar).
    private let tabs: [AppMode] = [.teleport, .route, .joystick]

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    switch selectedMode {
                    case .teleport: teleportCard
                    case .route:    routeCard
                    case .joystick: JoystickControlView()
                    case .settings: teleportCard
                    }
                }
                .padding(DS.Spacing.sm)
            }

            // Docked execution authority (mockup btn-primary at panel bottom).
            PrimaryActionPill(mode: selectedMode, fullWidth: true)
                .padding(DS.Spacing.sm)
        }
        .frame(width: DS.Metrics.mapRoutePanelMaxWidth)
        .frame(maxHeight: .infinity)
        .background(DS.Color.backgroundSecondary)
        .accessibilityIdentifier("modeControlPanel")
    }

    // MARK: - Tab strip (mockup .tabs)

    private var tabStrip: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(DS.Spacing.xxs)
        .background(DS.Color.backgroundPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modeTabStrip")
    }

    private func tabButton(_ tab: AppMode) -> some View {
        let isSelected = selectedMode == tab
        let accent = DS.ModeAccent.forMode(tab)
        return Button {
            withAnimation(DS.Animation.fast) { selectedMode = tab }
        } label: {
            Text(tab.rawValue)
                .font(isSelected ? DS.Typography.labelPrimary : DS.Typography.labelSecondary)
                .foregroundStyle(isSelected ? accent.base : DS.Color.foregroundSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(isSelected ? accent.soft : Color.clear)
                )
                .overlay(alignment: .bottom) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DS.Metrics.strokeWidth, style: .continuous)
                            .fill(accent.base)
                            .frame(height: DS.Metrics.two)
                            .padding(.horizontal, DS.Spacing.sm)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.rawValue) mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Teleport card (mockup Teleport to Location)

    private var teleportCard: some View {
        FloatingControlPanel(title: "Teleport", icon: "location.fill", accent: DS.ModeAccent.teleport.base) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                targetSummary

                PCFieldShell(label: "Latitude", prefix: "Lat", isFocused: focusedField == .latitude) {
                    TextField("0.000000", text: $latitudeInput)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .latitude)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Location.latitudeField)
                }

                PCFieldShell(label: "Longitude", prefix: "Lng", isFocused: focusedField == .longitude) {
                    TextField("0.000000", text: $longitudeInput)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .longitude)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Location.longitudeField)
                }

                Button {
                    applyCoordinatesToTarget()
                } label: {
                    Label("Set Target", systemImage: "mappin")
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent))
                .disabled(coordinateApplyDisabledReason != nil)
                .help(coordinateApplyDisabledReason ?? "Apply entered coordinates as the target")
                .accessibilityIdentifier(AccessibilityIdentifiers.Location.setLocationButton)
            }
        }
    }

    private var targetSummary: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: appState.targetLocation == nil ? "mappin" : "scope")
                .foregroundStyle(appState.targetLocation == nil ? DS.Color.foregroundTertiary : DS.Color.mockupViolet)
            VStack(alignment: .leading, spacing: 0) {
                Text(appState.targetLocationName ?? "No target selected")
                    .font(DS.Typography.labelPrimary)
                    .foregroundStyle(DS.Color.foregroundPrimary)
                    .lineLimit(1)
                Text(appState.targetLocation?.formattedShort ?? "Tap map, search, or enter coordinates")
                    .font(DS.Typography.monoSmall)
                    .foregroundStyle(DS.Color.foregroundTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Route card (mockup Route Builder)

    private var routeCard: some View {
        FloatingControlPanel(title: "Multi-Spot", icon: "point.topleft.down.curvedto.point.bottomright.up", accent: DS.ModeAccent.multiSpot.base) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    Button {
                        appState.addRoutePoint()
                    } label: {
                        Label("Add Waypoint", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                    .disabled(appState.targetLocation == nil)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Route.addWaypointButton)

                    Button { appState.showRouteImport = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: DS.Metrics.mapRoutePanelButtonSize, height: DS.Metrics.mapRoutePanelButtonSize)
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    .accessibilityIdentifier(AccessibilityIdentifiers.Route.importButton)

                    Button { appState.clearRoute() } label: {
                        Image(systemName: "trash")
                            .frame(width: DS.Metrics.mapRoutePanelButtonSize, height: DS.Metrics.mapRoutePanelButtonSize)
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcDanger))
                    .disabled(appState.currentRoute.isEmpty)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Route.clearRouteButton)
                }

                if appState.currentRoute.isEmpty {
                    Label("Select a spot, then Add Waypoint.", systemImage: "info.circle")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.foregroundTertiary)
                } else {
                    ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                        waypointRow(index: index, coordinate: coord)
                    }
                }
            }
        }
    }

    private func waypointRow(index: Int, coordinate: LocationCoordinate) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text("\(index + 1)")
                .font(DS.Typography.monoSmall)
                .foregroundStyle(DS.Color.mockupSky)
                .frame(width: DS.Metrics.mapRouteCounterHeight, height: DS.Metrics.mapRouteCounterHeight)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.ModeAccent.multiSpot.soft)
                )
            Text(coordinate.formattedShort)
                .font(DS.Typography.monoSmall)
                .foregroundStyle(DS.Color.foregroundPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { appState.removeRoutePoint(at: index) } label: {
                Image(systemName: "xmark")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove waypoint \(index + 1)")
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Color.backgroundElevated.opacity(DS.Opacity.panel))
        )
    }

    // MARK: - Actions (subordinate: target-only)

    private var coordinateApplyDisabledReason: String? {
        if latitudeInput.isEmpty || longitudeInput.isEmpty { return "Enter latitude and longitude" }
        guard let lat = Double(latitudeInput), let lon = Double(longitudeInput) else { return "Enter valid decimal coordinates" }
        guard LocationCoordinate(latitude: lat, longitude: lon).isValid else { return "Latitude must be -90...90; longitude -180...180" }
        return nil
    }

    private func applyCoordinatesToTarget() {
        guard let lat = Double(latitudeInput), let lon = Double(longitudeInput) else { return }
        let coordinate = LocationCoordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else { return }
        withAnimation {
            appState.targetLocation = coordinate
            appState.targetLocationName = "Custom location"
            appState.statusMessage = String(format: "Selected target: %.4f, %.4f. Use the primary action pill to apply it to the device.", coordinate.latitude, coordinate.longitude)
        }
    }
}

#if DEBUG
struct ModeControlPanel_Previews: PreviewProvider {
    static var previews: some View {
        ModeControlPanel(selectedMode: .constant(.teleport))
            .environmentObject(AppState())
            .environmentObject(TunneldManager.shared)
            .frame(height: DS.Metrics.shellPreviewHeight)
    }
}
#endif
