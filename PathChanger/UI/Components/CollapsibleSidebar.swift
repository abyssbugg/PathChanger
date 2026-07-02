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

    @StateObject private var searchService = LocationSearchService()
    @State private var showSearchResults = false
    @FocusState private var isSearchFocused: Bool


    var body: some View {
        VStack(spacing: DS.Metrics.zero) {
            topGutter

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                searchField
                modePicker

                Text("RECENT LOCATIONS")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundTertiary)
                    .textCase(.uppercase)
                    .padding(.top, DS.Spacing.xs)

                if appState.locationHistory.isEmpty {
                    emptyRecents
                } else {
                    recentsList
                }

                Spacer(minLength: DS.Metrics.zero)
                footer
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.sm)
        }
        .frame(width: DS.Metrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(DS.Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(DS.Color.backgroundElevated.opacity(DS.Opacity.panel))
                .allowsHitTesting(false)
        )
        .overlay(
            Rectangle()
                .fill(DS.Color.foregroundTertiary)
                .frame(width: DS.Metrics.strokeWidth)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .top) {
            if showSearchResults && !searchService.searchResults.isEmpty {
                searchResultsDropdown
                    .padding(.top, DS.Metrics.sidebarSearchDropdownTopInset)
                    .padding(.horizontal, DS.Spacing.sm)
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
                    .font(DS.Typography.labelPrimary)
                    .foregroundStyle(DS.Color.foregroundSecondary)
                    .frame(width: DS.Metrics.sidebarCollapseButtonSize, height: DS.Metrics.sidebarCollapseButtonSize)
                    .background(DS.Color.backgroundElevated, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                            .stroke(DS.Color.foregroundTertiary, lineWidth: DS.Metrics.strokeWidth)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide sidebar")
            .accessibilityHint("Collapses the navigation sidebar")
            .accessibilityIdentifier("mapShellSidebarCollapseButton")
        }
        .padding(.horizontal, DS.Spacing.sm)
        .frame(height: DS.Metrics.sidebarTopGutterHeight)
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

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach([AppMode.teleport, .route, .joystick], id: \.self) { mode in
                modeSegment(mode)
            }
        }
        .padding(DS.Spacing.xxs)
        .frame(height: DS.Metrics.sidebarControlHeight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Color.backgroundElevated.opacity(DS.Opacity.idleRow))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.Simulation.modeSelector)
    }

    private func modeSegment(_ mode: AppMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            selectedMode = mode
        } label: {
            Text(mode.rawValue)
                .font(isSelected ? DS.Typography.labelPrimary : DS.Typography.labelSecondary)
                .foregroundStyle(isSelected ? DS.Color.foregroundPrimary : DS.Color.foregroundSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(isSelected ? DS.Color.accent.opacity(DS.Opacity.selectionTint) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.rawValue) mode")
    }

    // MARK: - Recents

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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundTertiary)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("mapShellSettingsButton")
        }
        .padding(.top, DS.Spacing.xs)
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