//
//  LibraryFlyout.swift
//  PathChanger
//
//  Left slide-in Library flyout — the SwiftUI port of the mockup's `.flyout`
//  (geospoofer-pro.html): Favorites / History lists that slide in over the
//  map, dismiss on scrim click, the X button, or Escape.
//
//  Subordinate by design: selecting a place sets the TARGET only (same
//  semantics as the sidebar's context selection) and closes. It never calls
//  startSimulation/stopSimulation/setLocation — PrimaryActionPill remains the
//  SOLE production T0 execution authority.
//

import SwiftUI

/// Which library list the flyout shows.
enum LibraryKind: String, Identifiable, CaseIterable {
    case favorites
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: return "Favorites"
        case .history:   return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .favorites: return "star.fill"
        case .history:   return "clock.arrow.circlepath"
        }
    }

    var emptyMessage: String {
        switch self {
        case .favorites: return "Saved places appear here"
        case .history:   return "Recent locations appear here"
        }
    }
}

/// A unified row model so Favorites and History render identically.
struct LibraryPlace: Identifiable {
    let id: String
    let name: String
    let coordinate: LocationCoordinate
    let icon: String
}

struct LibraryFlyout: View {
    let kind: LibraryKind
    @Binding var isPresented: Bool
    /// Subordinate selection: sets the target only. Provided by the shell.
    let onSelect: (LocationCoordinate, String) -> Void

    @EnvironmentObject var appState: AppState
    @ObservedObject private var favorites = LocationFavoritesManager.shared

    var body: some View {
        ZStack(alignment: .leading) {
            // Scrim: click-outside-to-dismiss (mockup document mousedown handler).
            Color.black.opacity(DS.Opacity.previewDim)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .accessibilityLabel("Dismiss \(kind.title)")
                .accessibilityAddTraits(.isButton)

            panel
                .transition(.move(edge: .leading))
        }
        .zIndex(10)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.Color.foregroundTertiary.opacity(DS.Opacity.divider))

            if places.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.xxs) {
                        ForEach(places) { place in
                            row(place)
                        }
                    }
                    .padding(DS.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: DS.Metrics.popoverWidth)
        .frame(maxHeight: .infinity)
        .dsGlassSurface(cornerRadius: 0)
        .accessibilityIdentifier("libraryFlyout")
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(DS.Color.foregroundSecondary)
            Text(kind.title)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.foregroundPrimary)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(DS.Typography.labelPrimary)
                    .foregroundStyle(DS.Color.foregroundSecondary)
                    .frame(width: DS.Metrics.iconButtonSize, height: DS.Metrics.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction) // Escape closes (mockup parity)
            .accessibilityLabel("Close \(kind.title)")
            .accessibilityIdentifier("libraryFlyoutClose")
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var emptyState: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(DS.Color.inactive)
            Text(kind.emptyMessage)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
    }

    private func row(_ place: LibraryPlace) -> some View {
        Button {
            onSelect(place.coordinate, place.name)
            close()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: place.icon)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundSecondary)
                    .frame(width: DS.Metrics.iconButtonSize, height: DS.Metrics.iconButtonSize)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Color.backgroundElevated.opacity(DS.Opacity.panel))
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(place.name)
                        .font(DS.Typography.labelPrimary)
                        .foregroundStyle(DS.Color.foregroundPrimary)
                        .lineLimit(1)
                    Text(place.coordinate.formattedShort)
                        .font(DS.Typography.monoSmall)
                        .foregroundStyle(DS.Color.foregroundTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.xs)

                Image(systemName: "chevron.right")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundTertiary)
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .appHoverOverlay(cornerRadius: DS.Radius.chip)
        .accessibilityLabel("Select \(place.name)")
    }

    /// Rows for the active kind, mapped from the real stores.
    private var places: [LibraryPlace] {
        switch kind {
        case .favorites:
            return favorites.favorites.map {
                LibraryPlace(id: $0.id.uuidString, name: $0.name, coordinate: $0.coordinate, icon: "mappin")
            }
        case .history:
            return appState.locationHistory.map {
                LibraryPlace(id: $0.id.uuidString, name: $0.displayName, coordinate: $0.coordinate, icon: "clock")
            }
        }
    }

    private func close() {
        withAnimation(DS.Animation.slow) { isPresented = false }
    }
}

#if DEBUG
struct LibraryFlyout_Previews: PreviewProvider {
    static var previews: some View {
        LibraryFlyout(kind: .favorites, isPresented: .constant(true)) { _, _ in }
            .environmentObject(AppState())
            .frame(width: DS.Metrics.shellPreviewWidth, height: DS.Metrics.shellPreviewHeight)
    }
}
#endif
