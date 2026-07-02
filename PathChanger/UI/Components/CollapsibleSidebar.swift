//
//  CollapsibleSidebar.swift
//  PathChanger
//
//  Context/navigation-only sidebar for map shell interactions.
//

import SwiftUI

struct CollapsibleSidebar: View {
    @Binding var selectedMode: AppMode
    @Binding var isShowingSettings: Bool
    @EnvironmentObject var appState: AppState
    var onCollapse: () -> Void = {}
    /// Opens the Library flyout (mockup nav-item parity). Subordinate
    /// navigation only — the flyout itself performs target-only selection.
    var onOpenLibrary: (LibraryKind) -> Void = { _ in }

    @StateObject private var searchService = LocationSearchService()
    @State private var showSearchResults = false
    @FocusState private var isSearchFocused: Bool


    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            searchField
                .padding(.top, DS.Spacing.sm)

            Text("LIBRARY")
                .font(DS.Typography.labelCaps)
                .foregroundStyle(DS.Color.foregroundTertiary)
                .tracking(DS.Metrics.shortcutLabelTracking)
                .padding(.top, DS.Spacing.xs)

            navItem(
                title: "History",
                subtitle: "Recent locations",
                icon: "clock.arrow.circlepath",
                identifier: "mapShellHistoryButton",
                accessibility: "Open history"
            ) { onOpenLibrary(.history) }

            navItem(
                title: "Favorites",
                subtitle: "Saved places",
                icon: "star",
                identifier: "mapShellFavoritesButton",
                accessibility: "Open favorites"
            ) { onOpenLibrary(.favorites) }

            navItem(
                title: "Settings",
                subtitle: "App & preferences",
                icon: "gearshape",
                identifier: "mapShellSettingsButton",
                accessibility: "Settings"
            ) { isShowingSettings = true }

            Text("RECENT LOCATIONS")
                .font(DS.Typography.labelCaps)
                .foregroundStyle(DS.Color.foregroundTertiary)
                .tracking(DS.Metrics.shortcutLabelTracking)
                .padding(.top, DS.Spacing.xs)

            if appState.locationHistory.isEmpty {
                emptyRecents
            } else {
                recentsList
            }

            Spacer(minLength: DS.Metrics.zero)

            sessionCard

            Text("PATHCHANGER · BUILD 1.0.0")
                .font(DS.Typography.monoSmall)
                .foregroundStyle(DS.Color.foregroundTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, DS.Spacing.xs)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .frame(width: DS.Metrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(DS.Color.backgroundSecondary)
        .overlay(alignment: .top) {
            if showSearchResults && !searchService.searchResults.isEmpty {
                searchResultsDropdown
                    .padding(.top, DS.Metrics.sidebarControlHeight + DS.Spacing.md)
                    .padding(.horizontal, DS.Spacing.sm)
            }
        }
        .accessibilityIdentifier("mapShellSidebar")
    }

    // MARK: - Collapse affordance
    //
    // The shell topbar hosts the visible sidebar toggle in the redesigned
    // layout; the rail keeps its own collapse affordance for accessibility
    // and the ⌘\ shortcut path.

    private var collapseButton: some View {
        Button(action: onCollapse) {
            Image(systemName: "sidebar.leading")
                .font(DS.Typography.labelPrimary)
                .foregroundStyle(DS.Color.foregroundSecondary)
                .frame(width: DS.Metrics.sidebarCollapseButtonSize, height: DS.Metrics.sidebarCollapseButtonSize)
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide sidebar")
        .accessibilityHint("Collapses the navigation sidebar")
        .accessibilityIdentifier("mapShellSidebarCollapseButton")
    }

    // MARK: - Library nav items (mockup .nav-item)

    private func navItem(
        title: String,
        subtitle: String,
        icon: String,
        identifier: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Typography.labelPrimary)
                    .foregroundStyle(DS.Color.foregroundSecondary)
                    .frame(width: DS.Metrics.iconButtonSize, height: DS.Metrics.iconButtonSize)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Color.backgroundElevated)
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(DS.Typography.labelPrimary)
                        .foregroundStyle(DS.Color.foregroundPrimary)
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.foregroundTertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .appHoverOverlay(cornerRadius: DS.Radius.chip)
        .accessibilityLabel(accessibility)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Session card (mockup .session-card)

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(appState.isSimulating ? DS.Color.mockupEmerald : DS.Color.inactive)
                    .frame(width: DS.Metrics.statusChipDotSize, height: DS.Metrics.statusChipDotSize)
                Text(appState.isSimulating ? (appState.statusMessage ?? "Spoofing Active") : "Standby")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.foregroundPrimary)
                    .lineLimit(1)
                collapseButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(TelemetryBar.coordinateText(appState.currentLocation ?? appState.targetLocation))
                .font(DS.Typography.monoSmall)
                .foregroundStyle(DS.Color.foregroundTertiary)
                .lineLimit(1)
        }
        .padding(DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.backgroundElevated.opacity(DS.Opacity.selectedRow))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.foregroundTertiary.opacity(DS.Opacity.divider), lineWidth: DS.Metrics.strokeWidth)
        )
        .accessibilityIdentifier("sidebarSessionCard")
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.foregroundSecondary)

            TextField("Search a place", text: $searchService.searchText)
                .textFieldStyle(.plain)
                .font(DS.Typography.labelSecondary)
                .foregroundStyle(DS.Color.foregroundPrimary)
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
                ProgressView()
                    .controlSize(.small)
            }

            if !searchService.searchText.isEmpty {
                Button {
                    searchService.clearSearch()
                    showSearchResults = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.foregroundSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .frame(height: DS.Metrics.sidebarControlHeight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Color.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(isSearchFocused ? DS.Color.accent : DS.Color.foregroundTertiary, lineWidth: DS.Metrics.strokeWidth)
        )
    }

    // MARK: - Recents
    //
    // Mode selection moved to the right control panel's tab strip
    // (ModeControlPanel, mockup .tabs); the sidebar keeps `selectedMode`
    // only for its mode-aware selection semantics in `select(coordinate:)`.

    private var emptyRecents: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "clock")
                .foregroundStyle(DS.Color.foregroundSecondary)
            Text("Successful locations appear here")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var recentsList: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xxs) {
                ForEach(appState.locationHistory.prefix(6)) { entry in
                    recentRow(entry)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.History.historyList)
    }

    private func recentRow(_ entry: LocationHistoryEntry) -> some View {
        Button {
            select(coordinate: entry.coordinate, name: entry.displayName)
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(entry.displayName)
                    .font(DS.Typography.labelPrimary)
                    .foregroundStyle(DS.Color.foregroundPrimary)
                    .lineLimit(1)

                Text(entry.coordinate.formattedShort)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.Color.accent.opacity(DS.Opacity.selectionTint))
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent location \(entry.displayName)")
        .accessibilityIdentifier(AccessibilityIdentifiers.History.historyRow)
    }


    // MARK: - Search results dropdown

    private var searchResultsDropdown: some View {
        VStack(alignment: .leading, spacing: DS.Metrics.zero) {
            ForEach(searchService.searchResults.prefix(5)) { result in
                Button {
                    select(searchResult: result)
                } label: {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(result.name)
                            .font(DS.Typography.labelPrimary)
                            .foregroundStyle(DS.Color.foregroundPrimary)
                        Text(result.subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.foregroundSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.xs)
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
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .fill(DS.Color.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .stroke(DS.Color.foregroundTertiary, lineWidth: DS.Metrics.strokeWidth)
        )
        .shadow(
            color: .black.opacity(DS.Opacity.idleRow),
            radius: DS.Spacing.sm,
            x: DS.Metrics.zero,
            y: DS.Spacing.xs
        )
    }

    private func select(searchResult result: LocationSearchResult) {
        select(coordinate: result.coordinate, name: result.name)
    }

    private func select(coordinate: LocationCoordinate, name: String) {
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
        .frame(height: DS.Metrics.sidebarWidth + DS.Metrics.sidebarWidth)
    }
}
#endif