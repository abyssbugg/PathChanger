//
//  SavedPlacesCard.swift
//  PathChanger
//
//  Saved & history flyout from the pctnhc mock.
//

import SwiftUI

enum SavedTab: String, CaseIterable {
    case favorites = "Favorites"
    case places = "Places"
    case recent = "Recent"
}

struct SavedPlacesCard: View {
    @ObservedObject private var favorites = LocationFavoritesManager.shared
    @Binding var tab: SavedTab
    let onSelect: (LocationCoordinate, String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("SAVED & HISTORY")
                    .font(Organic.body(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Organic.neutral600)
                Spacer()
                if !items.isEmpty {
                    Button(action: clearTab) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .bold))
                            Text(tab == .recent ? "Clear" : "Clear all")
                                .font(Organic.body(10, weight: .bold))
                        }
                        .foregroundStyle(Organic.neutral700)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Organic.neutral600)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 11)
            .padding(.top, 11)
            .padding(.bottom, 8)

            HStack(spacing: 2) {
                ForEach(SavedTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        HStack(spacing: 5) {
                            Text(item.rawValue)
                            Text("\(count(for: item))")
                                .font(Organic.mono(10, weight: .bold))
                                .padding(.horizontal, 5)
                                .background(tab == item ? Organic.neutral200 : Organic.neutral100.opacity(0.5))
                                .clipShape(Capsule())
                        }
                        .font(Organic.body(11, weight: .bold))
                        .foregroundStyle(Organic.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(tab == item ? Organic.neutral100 : Color.clear)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Organic.neutral300)
            .clipShape(Capsule())
            .padding(.horizontal, 11)
            .padding(.bottom, 9)

            ScrollView {
                VStack(spacing: 5) {
                    if items.isEmpty {
                        Text(emptyText)
                            .font(Organic.body(11))
                            .foregroundStyle(Organic.neutral600)
                            .multilineTextAlignment(.center)
                            .padding(20)
                    } else {
                        ForEach(items) { item in
                            HStack(spacing: 2) {
                                Button {
                                    onSelect(item.coordinate, item.name)
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: tab == .favorites ? "star.fill" : (tab == .recent ? "clock" : "mappin.circle"))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Organic.accent600)
                                            .frame(width: 22, height: 22)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.name)
                                                .font(Organic.body(12, weight: .bold))
                                                .lineLimit(1)
                                            Text(item.coordinate.formattedShort)
                                                .font(Organic.mono(10))
                                                .foregroundStyle(Organic.neutral600)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button {
                                    remove(item)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Organic.neutral600)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 9)
            }
            .frame(maxHeight: 268)
        }
        .frame(width: 336)
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.18), radius: 18, y: 8)
    }

    private var items: [FavoriteLocation] {
        switch tab {
        case .favorites: return favorites.favorites
        case .places: return favorites.places
        case .recent: return favorites.recents
        }
    }

    private func count(for tab: SavedTab) -> Int {
        switch tab {
        case .favorites: return favorites.favorites.count
        case .places: return favorites.places.count
        case .recent: return favorites.recents.count
        }
    }

    private var emptyText: String {
        switch tab {
        case .favorites: return "Star a place from the map or a route stop."
        case .places: return "Places you pick stay here after you unstar them."
        case .recent: return "Locations you move to will show up here."
        }
    }

    private func clearTab() {
        switch tab {
        case .favorites: favorites.clearFavorites()
        case .places: favorites.clearPlaces()
        case .recent: favorites.clearRecents()
        }
    }

    private func remove(_ item: FavoriteLocation) {
        switch tab {
        case .favorites: favorites.removeFavorite(id: item.id)
        case .places: favorites.removePlace(id: item.id)
        case .recent: favorites.removeRecent(id: item.id)
        }
    }
}
