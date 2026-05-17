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
// MARK: - W1 Authority Declaration (Slice S0 — documentation only)
//
// MainMapShell is the SOLE production shell layout authority.
//
// Authority rules (frozen — see W1 governance plan):
//   - This shell is the only production layout. `ContentView` always
//     instantiates MainMapShell, and MainMapShell always instantiates
//     `SimulationView(mode: ..., chrome: .shell)`. The `.shell` chrome is
//     therefore the sole production layout authority.
//   - The shell hosts exactly three floating canonical surfaces:
//       (a) the Phase-1 readiness pill (`DeviceTunnelPill`),
//       (b) the T0 execution pill (`PrimaryActionPill`),
//       (c) the production sidebar (`CollapsibleSidebar`).
//     All three are placed by this shell and must not be relocated,
//     duplicated, or shadowed by any other layout.
//   - `.full` chrome surfaces in `SimulationView`, and the legacy
//     `SidebarView`, are compatibility shims not reachable through this
//     shell. They are deferred to the future `.full` deprecation phase
//     (W4) and are not active production authorities.
//
// W1 Slice S0 is documentation-only. No behavior, layout, state, bindings,
// or routing are altered by this declaration.
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
            SimulationView(mode: selectedMode, chrome: .shell)
                .ignoresSafeArea()

            // Sidebar (slides in from the leading edge when expanded).
            if isSidebarExpanded {
                CollapsibleSidebar(
                    selectedMode: $selectedMode,
                    isShowingSettings: $isShowingSettings
                )
                .transition(.move(edge: .leading))
                .zIndex(1)
            }

            // Sidebar toggle button (only shown when collapsed).
            if !isSidebarExpanded {
                SidebarToggleButton {
                    toggleSidebar()
                }
                .padding(.leading, 16)
                .padding(.top, 56)
                .zIndex(2)
            }

            // Top-right device pill.
            VStack {
                HStack {
                    Spacer()
                    DeviceTunnelPill()
                        .padding(.top, 24)
                        .padding(.trailing, 24)
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
                        .padding(.bottom, 28)
                    Spacer()
                }
            }
            .zIndex(4)

            // Hidden button to host the ⌘\ keyboard shortcut.
            Button(action: toggleSidebar) {
                Color.clear.frame(width: 1, height: 1)
            }
            .keyboardShortcut("\\", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isSidebarExpanded)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 540)
        }
        .onChange(of: isSidebarExpanded) { _, newValue in
            // Persist user preference so the toggle survives across launches.
            AppPreferences.shared.isSidebarExpanded = newValue
        }
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isSidebarExpanded.toggle()
        }
    }
}

#if DEBUG
struct MainMapShell_Previews: PreviewProvider {
    static var previews: some View {
        MainMapShell()
            .environmentObject(AppState())
            .environmentObject(TunneldManager.shared)
            .frame(width: 1100, height: 720)
    }
}
#endif
