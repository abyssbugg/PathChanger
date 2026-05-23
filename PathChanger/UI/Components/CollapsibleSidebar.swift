//
//  CollapsibleSidebar.swift
//  PathChanger
//
//  240pt-wide glass sidebar used by `MainMapShell`. Hosts:
//   - traffic-light spacer (56pt top inset)
//   - search field (binds to `LocationSearchService`)
//   - 3-segment mode picker
//   - "RECENT LOCATIONS" header + rows
//   - footer cog that opens SettingsView as a sheet
//
//  This view does NOT own the map — it only emits selection events through
//  bindings provided by the shell (selected mode, settings sheet, target
//  location). It is intentionally narrower than the current production
//  `SidebarView` because the device chooser now lives inside the top-right
//  device pill.
//

import SwiftUI

struct CollapsibleSidebar: View {
    @Binding var selectedMode: AppMode
    @Binding var isShowingSettings: Bool
    @EnvironmentObject var appState: AppState
    var onCollapse: () -> Void = {}

    @StateObject private var searchService = LocationSearchService()
    @State private var showSearchResults = false
    @FocusState private var isSearchFocused: Bool
    private enum SelectionSource {
        case search
        case recent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Traffic-light gutter so the sidebar's content sits below the
            // window controls. The native traffic lights are drawn by the
            // window itself; we just reserve space.
            topGutter

            VStack(alignment: .leading, spacing: 14) {
                searchField
                modePicker

                Text("RECENT LOCATIONS")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.pcTextMutedDynamic)
                    .padding(.top, 6)

                if appState.locationHistory.isEmpty {
                    emptyRecents
                } else {
                    recentsList
                }

                Spacer(minLength: 0)

                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        // Slice F1 (UX remediation): both decorative overlay rectangles must be
        // hit-test-transparent. A `Rectangle().fill(...)` overlay without
        // `.allowsHitTesting(false)` absorbs every tap, silently blocking the
        // mode picker, recent locations, settings cog, and search field that
        // live BELOW these overlays. Visual appearance, glass styling, layout,
        // and accessibility semantics are unchanged.
        .overlay(
            Rectangle()
                .fill(Color.pcSurfaceTintDynamic)
                .allowsHitTesting(false)
        )
        .overlay(
            Rectangle()
                .fill(Color.pcOutlineDynamic)
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .top) {
            // Search results dropdown — anchored just below the search field
            // so it floats over the recents list when active.
            if showSearchResults && !searchService.searchResults.isEmpty {
                searchResultsDropdown
                    .padding(.top, 56 + 16 + 32 + 4)
                    .padding(.horizontal, 16)
            }
        }
        .accessibilityIdentifier("mapShellSidebar")
    }

    // MARK: - Top gutter

    private var topGutter: some View {
        HStack {
            Spacer()
            Button(action: onCollapse) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.pcTextMutedDynamic)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.pcOutlineDynamic, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide sidebar")
            .accessibilityHint("Collapses the navigation sidebar")
            .accessibilityIdentifier("mapShellSidebarCollapseButton")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.pcTextMutedDynamic)
            TextField("Search a place", text: $searchService.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.pcTextDynamic)
                .focused($isSearchFocused)
                .onChange(of: searchService.searchText) { _, newValue in
                    showSearchResults = !newValue.isEmpty
                }
                .onSubmit {
                    if let first = searchService.searchResults.first {
                        select(searchResult: first)
                    }
                }
                .accessibilityLabel("Search location or coordinates")
                .accessibilityIdentifier("mapShellSearchField")

            if searchService.isSearching {
                ProgressView().scaleEffect(0.6)
            }

            if !searchService.searchText.isEmpty {
                Button {
                    searchService.clearSearch()
                    showSearchResults = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.pcTextMutedDynamic)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSearchFocused ? Color.pcSystemBlue.opacity(0.5) : Color.pcOutlineDynamic, lineWidth: 1)
        )
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach([AppMode.teleport, .route, .joystick], id: \.self) { mode in
                modeSegment(mode)
            }
        }
        .padding(2)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.Simulation.modeSelector)
    }

    private func modeSegment(_ mode: AppMode) -> some View {
        let isSelected = (selectedMode == mode)
        return Button {
            selectedMode = mode
        } label: {
            Text(mode.rawValue)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.pcTextDynamic : Color.pcTextMutedDynamic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.pcSurfaceTintDynamic : .clear)
                )
                .shadow(color: isSelected ? .black.opacity(0.10) : .clear, radius: 3, x: 0, y: 1)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.rawValue) mode")
    }

    // MARK: - Recents

    // W1 visual governance: recents are contextual interactions for target
    // selection only. They do not execute location changes or duplicate the
    // canonical PrimaryActionPill authority.
    private var emptyRecents: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(Color.pcTextMutedDynamic)
            Text("Successful locations appear here")
                .font(.system(size: 12))
                .foregroundStyle(Color.pcTextMutedDynamic)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var recentsList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(appState.locationHistory.prefix(6)) { entry in
                    recentRow(entry)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.History.historyList)
    }

    private func recentRow(_ entry: LocationHistoryEntry) -> some View {
        Button {
            select(coordinate: entry.coordinate, name: entry.displayName, source: .recent)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.pcTextDynamic)
                    .lineLimit(1)
                Text(entry.coordinate.formattedShort)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.pcTextMutedDynamic)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.pcSurfaceTintDynamic.opacity(0.4))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent location \(entry.displayName)")
        .accessibilityIdentifier(AccessibilityIdentifiers.History.historyRow)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pcTextMutedDynamic)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("mapShellSettingsButton")
        }
        .padding(.top, 8)
    }

    // MARK: - Search results dropdown

    // W1 visual governance: search results are contextual interactions that
    // select target context. Applying that target remains owned by the
    // canonical PrimaryActionPill.
    private var searchResultsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchService.searchResults.prefix(5)) { result in
                Button {
                    select(searchResult: result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.pcTextDynamic)
                        Text(result.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.pcTextMutedDynamic)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.clear)
                .contentShape(Rectangle())
                if result.id != searchService.searchResults.prefix(5).last?.id {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.pcOutlineDynamic, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    private func select(searchResult result: LocationSearchResult) {
        select(coordinate: result.coordinate, name: result.name, source: .search)
    }

    private func select(coordinate: LocationCoordinate, name: String, source: SelectionSource) {
        appState.targetLocation = coordinate
        appState.targetLocationName = name

        switch selectedMode {
        case .route:
            appState.addRoutePoint(coordinate)
            appState.targetLocationName = name
            let nextAction = source == .search ? "Search again for the next spot." : "Select another recent or search for the next spot."
            appState.statusMessage = "Added \(name) as waypoint \(appState.currentRoute.count). \(nextAction)"
        case .joystick:
            appState.statusMessage = "Selected \(name) as joystick start. Press the action pill to begin."
        case .teleport:
            appState.statusMessage = "Selected \(name). Press the action pill to apply."
        case .settings:
            appState.statusMessage = "Selected \(name)."
        }
        searchService.clearSearch()
        showSearchResults = false
        isSearchFocused = false
    }
}

#if DEBUG
struct CollapsibleSidebar_Previews: PreviewProvider {
    static var previews: some View {
        CollapsibleSidebar(
            selectedMode: .constant(.teleport),
            isShowingSettings: .constant(false)
        )
        .environmentObject(AppState())
        .frame(height: 700)
    }
}
#endif
