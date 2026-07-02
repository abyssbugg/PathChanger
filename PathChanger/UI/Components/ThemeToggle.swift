//
//  ThemeToggle.swift
//  PathChanger
//
//  Dark/light theme toggle — the SwiftUI port of the mockup's `#themeBtn`
//  icon button (geospoofer-pro.html): moon icon while dark, sun icon while
//  light, one click flips the theme, and the choice persists across launches
//  (mirroring the mockup's `localStorage['pc-theme']` behavior).
//
//  Theme application is a single `NSApp.appearance` override. Every DS color
//  is defined via dynamic NSColor providers (`Color.dynamic(light:dark:)`),
//  so flipping the app appearance restyles the entire UI with no per-view
//  work — this is exactly what the design-token layer was built for.
//
//  `AppTheme.applySaved()` must be called once at launch (PathChangerApp)
//  so a persisted override survives restarts. Default is `.system` (no
//  override), preserving current behavior for existing users.
//

import SwiftUI
import AppKit

/// Persisted appearance override. Raw values are stored in UserDefaults
/// (`ui.theme`) via AppPreferences.
enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// The persisted theme (defaults to `.system` when unset or invalid).
    static var saved: AppTheme {
        AppTheme(rawValue: AppPreferences.shared.appTheme) ?? .system
    }

    /// Persist and apply this theme to the whole app.
    @MainActor
    func apply() {
        AppPreferences.shared.appTheme = rawValue
        NSApp.appearance = nsAppearance
    }

    /// Apply the persisted theme without changing it. Call once at launch.
    @MainActor
    static func applySaved() {
        NSApp.appearance = saved.nsAppearance
    }
}

struct ThemeToggle: View {
    @State private var isDarkActive: Bool = ThemeToggle.isEffectivelyDark()
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isDarkActive ? "moon" : "sun.max")
                .font(.system(size: DS.Metrics.iconButtonIconSize, weight: .regular))
                .foregroundStyle(isHovered ? DS.Color.foregroundPrimary : DS.Color.foregroundSecondary)
                .frame(width: DS.Metrics.iconButtonSize, height: DS.Metrics.iconButtonSize)
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(isHovered ? DS.Color.backgroundElevated : DS.Color.backgroundSecondary.opacity(DS.Opacity.panel))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(
                    DS.Color.foregroundTertiary.opacity(isHovered ? DS.Opacity.outline : DS.Opacity.divider),
                    lineWidth: DS.Metrics.strokeWidth
                )
        )
        .onHover { hovering in
            withAnimation(DS.Animation.fast) { isHovered = hovering }
        }
        .accessibilityIdentifier("themeToggle")
        .accessibilityLabel(isDarkActive ? "Switch to light theme" : "Switch to dark theme")
    }

    private func toggle() {
        let next: AppTheme = isDarkActive ? .light : .dark
        withAnimation(DS.Animation.standard) {
            next.apply()
            isDarkActive = (next == .dark)
        }
    }

    /// Whether the app is currently rendering dark, considering both an
    /// explicit override and the system appearance.
    static func isEffectivelyDark() -> Bool {
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

#if DEBUG
struct ThemeToggle_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Color.backgroundSecondary
            ThemeToggle()
        }
        .frame(
            width: DS.Metrics.iconButtonSize + DS.Spacing.xl,
            height: DS.Metrics.iconButtonSize + DS.Spacing.xl
        )
    }
}
#endif
