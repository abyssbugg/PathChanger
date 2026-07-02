//
//  MainMapShell.swift
//  PathChanger
//
//  New top-level layout for PathChanger's main window.
//
//  Replaces the previous `NavigationSplitView` chrome with an Apple-Maps-style
//  layout: a map-dominant background, a hybrid collapsible left sidebar, a
//  floating top-right device/tunnel pill, and a floating bottom-center primary
//  action pill.
//
//  Sidebar visibility is owned here (`@State isSidebarExpanded`, persisted via
//  `AppPreferences.isSidebarExpanded`), and toggled either by the sidebar
//  toggle button or via the ⌘\ keyboard shortcut.
//
//  Mode selection is owned here (`@State selectedMode`); the sidebar emits
//  changes via `@Binding`.
//
// MainMapShell is the single production shell layout authority.
//

import SwiftUI

struct MainMapShell: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager

    @State private var selectedMode: AppMode = .teleport
    @State private var isSidebarExpanded: Bool = AppPreferences.shared.isSidebarExpanded
    @State private var isShowingSettings: Bool = false
    @State private var activeLibrary: LibraryKind?

    var body: some View {
        ZStack {
            // Mockup window structure: topbar / (rail | map | control panel) / footer.
            VStack(spacing: 0) {
                topBar
                hairline

                HStack(spacing: 0) {
                    if isSidebarExpanded {
                        CollapsibleSidebar(
                            selectedMode: $selectedMode,
                            isShowingSettings: $isShowingSettings,
                            onCollapse: toggleSidebar,
                            onOpenLibrary: openLibrary
                        )
                        .transition(.move(edge: .leading))

                        verticalHairline
                    }

                    // Center: the REAL MapKit map, bounded to this region.
                    SimulationView(mode: selectedMode, embedded: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    verticalHairline
                    ModeControlPanel(selectedMode: $selectedMode)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                hairline
                TelemetryBar()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(DS.Color.backgroundPrimary)
            .animation(DS.Animation.slow, value: isSidebarExpanded)

            // Library flyout overlay (mockup .flyout): scrim tap / X / Escape.
            if let kind = activeLibrary {
                LibraryFlyout(
                    kind: kind,
                    isPresented: Binding(
                        get: { activeLibrary != nil },
                        set: { if !$0 { activeLibrary = nil } }
                    ),
                    onSelect: selectLibraryPlace
                )
                .zIndex(10)
            }

            // Hidden button to host the ⌘\ keyboard shortcut.
            Button(action: toggleSidebar) {
                Color.clear.frame(width: DS.Metrics.shellHiddenShortcutSize, height: DS.Metrics.shellHiddenShortcutSize)
            }
            .keyboardShortcut("\\", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheetContainer {
                isShowingSettings = false
            }
                .environmentObject(appState)
        }
        .onChange(of: isSidebarExpanded) { _, newValue in
            // Persist user preference so the toggle survives across launches.
            AppPreferences.shared.isSidebarExpanded = newValue
        }
    }

    // MARK: - Top bar (mockup .topbar)

    private var topBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            brandBlock
            sidebarToggle

            Spacer(minLength: DS.Spacing.sm)

            HStack(spacing: DS.Spacing.xs) {
                ConnectionPill()
                DeviceDropdown()
            }

            Spacer(minLength: DS.Spacing.sm)

            ThemeToggle()
        }
        // Leading inset clears the native traffic-light controls (hidden title bar).
        .padding(.leading, DS.Metrics.sidebarTopGutterHeight + DS.Spacing.md)
        .padding(.trailing, DS.Spacing.sm)
        .frame(height: DS.Metrics.sidebarTopGutterHeight)
        .frame(maxWidth: .infinity)
        .background(DS.Color.backgroundSecondary)
    }

    private var brandBlock: some View {
        HStack(spacing: DS.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.ModeAccent.teleport.gradient)
                    .frame(width: DS.Metrics.iconButtonSize, height: DS.Metrics.iconButtonSize)
                Image(systemName: "location.north.fill")
                    .font(.system(size: DS.Metrics.iconButtonIconSize - 2, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("PathChanger")
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(DS.Color.foregroundPrimary)
                Text("v1.0.0")
                    .font(DS.Typography.monoSmall)
                    .foregroundStyle(DS.Color.foregroundTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PathChanger version 1.0.0")
    }

    private var sidebarToggle: some View {
        Button(action: toggleSidebar) {
            Image(systemName: "sidebar.leading")
                .font(.system(size: DS.Metrics.iconButtonIconSize, weight: .regular))
                .foregroundStyle(DS.Color.foregroundSecondary)
                .frame(width: DS.Metrics.iconButtonSize, height: DS.Metrics.iconButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSidebarExpanded ? "Hide sidebar" : "Show sidebar")
        .accessibilityIdentifier("mapShellSidebarToggle")
    }

    private var hairline: some View {
        Rectangle()
            .fill(DS.Color.foregroundTertiary.opacity(DS.Opacity.divider))
            .frame(height: DS.Metrics.strokeWidth)
            .allowsHitTesting(false)
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(DS.Color.foregroundTertiary.opacity(DS.Opacity.divider))
            .frame(width: DS.Metrics.strokeWidth)
            .frame(maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    private func toggleSidebar() {
        withAnimation(DS.Animation.slow) {
            isSidebarExpanded.toggle()
        }
    }

    private func openLibrary(_ kind: LibraryKind) {
        withAnimation(DS.Animation.slow) {
            activeLibrary = kind
        }
    }

    /// Subordinate library selection: sets the target only, mirroring the
    /// sidebar's mode-aware context selection. Execution stays with
    /// PrimaryActionPill (SOLE production T0 execution authority).
    private func selectLibraryPlace(coordinate: LocationCoordinate, name: String) {
        appState.targetLocation = coordinate
        appState.targetLocationName = name
        switch selectedMode {
        case .route:
            appState.statusMessage = "Selected \(name) as route spot. Use Add Waypoint to include it in the route."
        case .joystick:
            appState.statusMessage = "Selected \(name) as joystick start. Press the action pill to begin."
        case .teleport:
            appState.statusMessage = "Selected \(name). Press the action pill to apply."
        case .settings:
            appState.statusMessage = "Selected \(name)."
        }
    }
}

private struct SettingsSheetContainer: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(DS.Typography.title)
                    .foregroundStyle(Color.pcText)

                Spacer()

                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mapShellSettingsDoneButton")
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(Color.pcSurface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.pcOutline.opacity(AppSurfaceAlpha.divider))
                    .frame(height: DS.Metrics.strokeWidth)
                    .allowsHitTesting(false)
            }

            SettingsView(showsHeader: false)
        }
        .frame(width: DS.Metrics.settingsContentMaxWidth, height: DS.Metrics.settingsSheetHeight)
        .background(Color.pcBackground)
    }
}

#if DEBUG
struct MainMapShell_Previews: PreviewProvider {
    static var previews: some View {
        MainMapShell()
            .environmentObject(AppState())
            .environmentObject(TunneldManager.shared)
            .frame(width: DS.Metrics.shellPreviewWidth, height: DS.Metrics.shellPreviewHeight)
    }
}
#endif
