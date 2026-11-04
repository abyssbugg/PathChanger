//
//  OrganicSettingsSheet.swift
//  PathChanger
//
//  The in-window Settings: a centred panel over the window, in grouped sections.
//

import SwiftUI

struct OrganicSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @ObservedObject private var favorites = LocationFavoritesManager.shared
    @Binding var isPresented: Bool
    @Binding var appearanceRaw: String

    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap: Bool = true
    @AppStorage("autoReconnectDevice") private var autoReconnect: Bool = true
    @AppStorage("keepLocationCentered") private var keepCentered: Bool = true
    @AppStorage("unitsMetric") private var unitsMetric: Bool = true
    @AppStorage("showStreetLabels") private var showStreetLabels: Bool = true

    // MARK: Placement

    /// Centred over the window, like a dialog (it used to slide in on the right).
    static let panelAlignment: Alignment = .center
    static let panelWidth: CGFloat = 600
    static let panelMaxHeight: CGFloat = 720
    /// The space kept between the panel and the window's edges.
    static let windowMargin: CGFloat = 40

    static func panelMaxSize(in window: CGSize) -> CGSize {
        CGSize(
            width: min(panelWidth, max(window.width - 2 * windowMargin, 0)),
            height: min(panelMaxHeight, max(window.height - 2 * windowMargin, 0))
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let size = Self.panelMaxSize(in: proxy.size)
            ZStack(alignment: Self.panelAlignment) {
                Organic.shadow.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .accessibilityHidden(true)

                panel
                    .frame(width: size.width)
                    .frame(maxHeight: size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .onExitCommand { isPresented = false }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Organic.neutral300).frame(height: 1)
            ContentHuggingLayout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        appearanceSection
                        connectionSection
                        movementSection
                        mapSection
                        savedDataSection
                        moreSettings
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous).fill(Organic.neutral100)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .strokeBorder(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.28), radius: 28, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settings.panel")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            OrganicGlyphView(glyph: .settings, size: 15)
                .foregroundStyle(Organic.accent800)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Organic.accent200))
                .accessibilityHidden(true)
            Text("Settings")
                .font(Organic.heading(20))
                .foregroundStyle(Organic.accent800)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Organic.neutral600)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Organic.neutral200))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
            .accessibilityLabel("Close Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Sections

    private var appearanceSection: some View {
        section("Appearance") {
            row("Theme", "Light or dark, for the window and the map") {
                OrganicSegmented(
                    options: OrganicAppearance.allCases,
                    selection: selectedAppearance,
                    title: { $0 == .light ? "Light" : "Dark" },
                    icon: { $0 == .light ? "sun.max" : "moon" },
                    onSelect: { appearanceRaw = $0.rawValue }
                )
                .fixedSize()
            }
        }
    }

    private var connectionSection: some View {
        section(
            "Connection",
            footnote: "Location changes become active only after the device acknowledges them."
        ) {
            row("iPhone", appState.selectedDevice.map { "\($0.displayName) · iOS \($0.iosVersion)" } ?? "None selected") {
                Button("Forget") { appState.selectedDevice = nil }
                    .buttonStyle(OrganicOutlineButtonStyle(tone: .accent))
                    .disabled(appState.selectedDevice == nil)
            }
            divider
            SettingsConnectionChoiceRow(
                deviceManager: appState.deviceManager,
                tunnel: tunneldManager,
                requiresLocationQuitDecision: { appState.requiresLocationQuitDecision }
            ) { title, detail, control in
                row(title, detail) { control }
            }
            divider
            row("Update frequency", "How often location is pushed to the device") {
                OrganicSegmented(
                    options: [1.0, 5.0, 10.0],
                    selection: appState.updateFrequencyHz,
                    title: { "\(Int($0)) Hz" },
                    onSelect: { appState.updateFrequencyHz = $0 }
                )
                .fixedSize()
            }
            divider
            toggleRow("Reconnect automatically", "Re-handshake when the device or transport switches", $autoReconnect)
        }
    }

    private var movementSection: some View {
        section("Movement") {
            row("Units", nil) {
                OrganicSegmented(
                    options: [true, false],
                    selection: unitsMetric,
                    title: { $0 ? "km" : "mi" },
                    onSelect: { unitsMetric = $0 }
                )
                .fixedSize()
            }
            divider
            row("Default travel mode", nil) {
                OrganicSegmented(
                    options: [SimulationSpeed.walking, .running, .cycling, .driving],
                    selection: appState.simulationSpeed,
                    title: settingsTravelLabel,
                    onSelect: { appState.setSpeed($0) }
                )
                .fixedSize()
            }
            divider
            toggleRow("Smooth turns", "Ease around corners instead of snapping", Binding(
                get: { appState.smoothTurns },
                set: { appState.smoothTurns = $0 }
            ))
        }
    }

    private var mapSection: some View {
        section("Map") {
            row("Basemap", nil) {
                OrganicSegmented(
                    options: [true, false],
                    selection: selectedAppearance == .light,
                    title: { $0 ? "Day" : "Night" },
                    onSelect: {
                        appearanceRaw = $0 ? OrganicAppearance.light.rawValue : OrganicAppearance.dark.rawValue
                    }
                )
                .fixedSize()
            }
            divider
            toggleRow("Street labels", "Draw road names over the basemap", $showStreetLabels)
            divider
            toggleRow("Show coordinates overlay", nil, $showCoordinatesOnMap)
            divider
            toggleRow("Keep location centred", "Pan the map to follow the pin while moving", $keepCentered)
        }
    }

    private var savedDataSection: some View {
        section("Saved data") {
            savedDataRow(
                "Built-in places",
                detail: "\(favorites.places.count) shown",
                actionLabel: "Restore",
                tone: .accent,
                action: favorites.restoreBuiltInPlaces
            )
            divider
            savedDataRow(
                "Location history",
                detail: historyDetail,
                actionLabel: "Clear",
                tone: .danger,
                action: favorites.clearRecents
            )
            divider
            savedDataRow(
                "Favorites",
                detail: "\(favorites.favorites.count) saved points",
                actionLabel: "Clear",
                tone: .danger,
                action: favorites.clearFavorites
            )
        }
    }

    /// The tunnel mode, diagnostics and the rest live in the app's Settings window.
    private var moreSettings: some View {
        HStack(spacing: 10) {
            Text("Tunnel mode, diagnostics and keyboard shortcuts are in the Settings window.")
                .font(Organic.body(11.5))
                .foregroundStyle(Organic.neutral600)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            SettingsLink {
                Text("Open Settings window…")
            }
            .buttonStyle(OrganicOutlineButtonStyle(tone: .neutral))
        }
    }

    // MARK: Building blocks

    private var divider: some View {
        Rectangle().fill(Organic.neutral300).frame(height: 1).padding(.leading, 14).accessibilityHidden(true)
    }

    /// A titled group of rows on one panel, with an optional note under it.
    private func section(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Organic.body(13, weight: .bold))
                .foregroundStyle(Organic.neutral800)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: Organic.radiusGroup, style: .continuous).fill(Organic.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusGroup, style: .continuous)
                    .strokeBorder(Organic.neutral300, lineWidth: 1)
            )
            if let footnote {
                Label(footnote, systemImage: "checkmark.shield")
                    .font(Organic.body(11.5))
                    .foregroundStyle(Organic.neutral600)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func row(_ title: String, _ subtitle: String?, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Organic.body(12.5, weight: .semibold))
                    .foregroundStyle(Organic.text)
                if let subtitle {
                    Text(subtitle)
                        .font(Organic.body(11))
                        .foregroundStyle(Organic.neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }

    private func toggleRow(_ title: String, _ subtitle: String?, _ value: Binding<Bool>) -> some View {
        row(title, subtitle) {
            Toggle(title, isOn: value)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Organic.sage600)
        }
    }

    private func savedDataRow(
        _ title: String,
        detail: String,
        actionLabel: String,
        tone: OrganicOutlineButtonStyle.Tone,
        action: @escaping () -> Void
    ) -> some View {
        row(title, detail) {
            Button(actionLabel, action: action)
                .buttonStyle(OrganicOutlineButtonStyle(tone: tone))
                .accessibilityLabel("\(actionLabel) \(title.lowercased())")
        }
    }

    private var selectedAppearance: OrganicAppearance {
        OrganicAppearance.persisted(appearanceRaw)
    }

    private var historyDetail: String {
        let count = favorites.recents.count
        return "\(count) \(count == 1 ? "entry" : "entries") · newest 14 kept"
    }

    private func settingsTravelLabel(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .walking: return "Walk"
        case .running: return "Run"
        case .cycling: return "Cycle"
        case .driving: return "Drive"
        default: return speed.displayName
        }
    }
}

/// Connect over, observing the device manager itself: AppState does not re-send its
/// connection-mode changes.
private struct SettingsConnectionChoiceRow<Row: View>: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var tunnel: TunneldManager
    /// Read when a choice is pressed.
    let requiresLocationQuitDecision: () -> Bool
    let row: (String, String, AnyView) -> Row
    @State private var pendingChange: ConnectionChoiceChange?

    var body: some View {
        let choice = ConnectionChoice.current(connectionMode: deviceManager.connectionMode, tunnelMode: tunnel.preferredMode)
        row("Connect over", choice.detail, AnyView(
            OrganicSegmented(
                options: ConnectionChoice.primary + ConnectionChoice.secondary,
                selection: choice,
                title: { $0.shortTitle },
                onSelect: { choice in
                    pendingChange = choice.select(
                        deviceManager: deviceManager,
                        tunnel: tunnel,
                        requiresLocationQuitDecision: requiresLocationQuitDecision()
                    )
                }
            )
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Connect over")
            .connectionChoiceConfirmation($pendingChange, deviceManager: deviceManager, tunnel: tunnel)
        ))
    }
}

/// A capsule outlined in its tone: the secondary button of the Settings panel. Danger
/// marks the actions that delete saved data.
struct OrganicOutlineButtonStyle: ButtonStyle {
    enum Tone { case accent, danger, neutral }

    let tone: Tone
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Organic.body(11.5, weight: .bold))
            .foregroundStyle(isEnabled ? ink : Organic.neutral500)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(configuration.isPressed ? Organic.neutral200 : Organic.neutral100))
            .overlay(Capsule().strokeBorder(isEnabled ? stroke : Organic.neutral300, lineWidth: 1))
            .contentShape(Capsule())
            .fixedSize()
    }

    private var ink: Color {
        switch tone {
        case .accent: return Organic.accent700
        case .danger: return Organic.danger
        case .neutral: return Organic.neutral800
        }
    }

    private var stroke: Color {
        switch tone {
        case .accent: return Organic.accent400
        case .danger: return Organic.danger.opacity(0.6)
        case .neutral: return Organic.neutral400
        }
    }
}
