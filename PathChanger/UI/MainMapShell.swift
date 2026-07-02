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

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bottom layer: map + mode-specific floating panels (in shell chrome).
            SimulationView(mode: selectedMode)
                .ignoresSafeArea()

            // Sidebar (slides in from the leading edge when expanded).
            if isSidebarExpanded {
                CollapsibleSidebar(
                    selectedMode: $selectedMode,
                    isShowingSettings: $isShowingSettings,
                    onCollapse: toggleSidebar
                )
                .transition(.move(edge: .leading))
                .zIndex(1)
            }

            // Sidebar toggle button (only shown when collapsed).
            if !isSidebarExpanded {
                SidebarToggleButton {
                    toggleSidebar()
                }
                .padding(.leading, DS.Metrics.shellSidebarToggleLeadingInset)
                .padding(.top, DS.Metrics.shellSidebarToggleTopInset)
                .zIndex(2)
            }

            // Top-right control cluster (mockup topbar port): live connection
            // state, device selector, and theme toggle on a glass surface.
            // ConnectionPill is the production Phase-1 readiness surface;
            // DeviceDropdown owns device selection; ThemeToggle owns appearance.
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: DS.Spacing.xs) {
                        ConnectionPill()
                        DeviceDropdown()
                        ThemeToggle()
                    }
                    .padding(DS.Spacing.xs)
                    .dsGlassSurface(cornerRadius: DS.Radius.pill)
                    .padding(.top, DS.Metrics.shellFloatingInset)
                    .padding(.trailing, DS.Metrics.shellFloatingInset)
                }
                Spacer()
            }
            .zIndex(3)

            // Bottom-center primary action pill.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PrimaryActionPill(mode: selectedMode)
                        .padding(.bottom, DS.Metrics.shellPrimaryPillBottomInset)
                    Spacer()
                }
            }
            .zIndex(4)

            // Hidden button to host the ⌘\ keyboard shortcut.
            Button(action: toggleSidebar) {
                Color.clear.frame(width: DS.Metrics.shellHiddenShortcutSize, height: DS.Metrics.shellHiddenShortcutSize)
            }
            .keyboardShortcut("\\", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .animation(DS.Animation.slow, value: isSidebarExpanded)
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

    private func toggleSidebar() {
        withAnimation(DS.Animation.slow) {
            isSidebarExpanded.toggle()
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
