//
//  DesignSystem.swift
//  PathChanger
//
//  Centralized design system for the professional macOS UI
//  Defines colors, typography, and common modifiers
//

import SwiftUI
import AppKit

// MARK: - Colors

extension Color {
    static let appPrimary = Color("AppPrimary") // Define in Assets or fallback
    static let appSecondary = Color("AppSecondary")
    static let appBackground = Color("AppBackground")
    static let appSurface = Color("AppSurface")

    // Fallbacks if assets are missing
    static let modernBlue = Color(hex: 0x007AFF)
    static let modernPurple = Color(hex: 0x5856D6)
    static let modernDarkSurface = Color(hex: 0x1C1C1E)
    static let modernDarkBackground = Color(hex: 0x000000)

    // PathChanger professional palette (legacy dark-only)
    static let pcBackground = Color(hex: 0x0B1326)
    static let pcSurface = Color(hex: 0x151C2D)
    static let pcSurfaceHigh = Color(hex: 0x1C2435)
    static let pcSurfaceHighest = Color(hex: 0x252D3E)
    static let pcPrimary = Color(hex: 0xADC6FF)
    static let pcAccent = Color(hex: 0x4D8DFF)
    static let pcSecondary = Color(hex: 0x4EDEA3)
    static let pcWarning = Color(hex: 0xFFB786)
    static let pcDanger = Color(hex: 0xFF6B7A)
    static let pcText = Color(hex: 0xD8DEEA)
    static let pcTextMuted = Color(hex: 0x8993A8)
    static let pcOutline = Color(hex: 0x343D50)

    // MARK: Dynamic (auto light/dark) tokens used by the new map shell

    /// Build a Color that resolves differently in light vs. dark appearances.
    /// Uses AppKit's `NSColor` dynamic provider so SwiftUI honors the system theme.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]) {
            case .darkAqua, .vibrantDark: return dark
            default: return light
            }
        }))
    }

    /// Primary text color that automatically adapts to system appearance.
    static let pcTextDynamic: Color = .dynamic(
        light: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        dark: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.99, alpha: 1.0)
    )

    /// Muted/secondary text color that adapts to appearance.
    static let pcTextMutedDynamic: Color = .dynamic(
        light: NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0),
        dark: NSColor(srgbRed: 0.62, green: 0.62, blue: 0.66, alpha: 1.0)
    )

    /// Subtle outline color that adapts to appearance.
    static let pcOutlineDynamic: Color = .dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.06),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06)
    )

    /// Tint applied behind glass surfaces (sits over `.regularMaterial`).
    static let pcSurfaceTintDynamic: Color = .dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55),
        dark: NSColor(srgbRed: 0.10, green: 0.105, blue: 0.125, alpha: 0.55)
    )

    /// System-blue accent. Same in both modes (matches Apple Maps + macOS).
    static let pcSystemBlue = Color(hex: 0x007AFF)

    /// Indigo used for the device-avatar gradient endpoint.
    static let pcSystemIndigo = Color(hex: 0x5856D6)
}

// MARK: - Action gradient + shadow constants

enum AppActionGradient {
    /// Primary action capsule gradient (matches Figma mockup).
    static let primary = LinearGradient(
        colors: [Color(hex: 0x0087FF), Color(hex: 0x0060EA)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Avatar gradient — system blue → indigo.
    static let avatar = LinearGradient(
        colors: [.pcSystemBlue, .pcSystemIndigo],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography

struct AppFont {
    static let title = Font.system(size: 18, weight: .semibold, design: .default)
    static let heading = Font.system(size: 16, weight: .semibold, design: .default)
    static let subheading = Font.system(size: 14, weight: .semibold, design: .default)
    static let label = Font.system(size: 13, weight: .medium, design: .default)
    static let body = Font.system(size: 13, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)
    static let metadata = Font.system(size: 12, weight: .regular, design: .default)
    static let monospace = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let labelCaps = Font.system(size: 12, weight: .medium, design: .default)
}

// MARK: - Spacing & Radius

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 16
}

enum AppSurfaceAlpha {
    static let idleRow: Double = 0.16
    static let hoverRow: Double = 0.22
    static let selectedRow: Double = 0.28
    static let activeRow: Double = 0.40
    static let inputField: Double = 0.72
    static let panel: Double = 0.94
    static let divider: Double = 0.45
    static let outline: Double = 0.55
}

// MARK: - Modifiers

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.lg)
            .background(Color.pcSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(Color.pcOutline.opacity(0.65), lineWidth: 1)
            )
    }
}

struct AppGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let strokeOpacity: Double
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.pcSurface.opacity(AppSurfaceAlpha.panel))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.pcOutline.opacity(strokeOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: 4, x: 0, y: 2)
    }
}

struct AppCapsuleButtonStyle: ButtonStyle {
    var accent: Color = .pcAccent
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.label)
            .foregroundStyle(isProminent ? Color.white : accent)
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(isProminent ? accent.opacity(configuration.isPressed ? 0.78 : 0.92) : accent.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .stroke(accent.opacity(isProminent ? 0.22 : 0.24), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }
}

/// The bottom-center primary action pill — gradient blue capsule with dual shadow.
/// Used by `PrimaryActionPill` in the new map shell.
struct AppCapsuleActionStyle: ButtonStyle {
    enum Tone {
        case accent
        case warning
        case danger

        var gradient: LinearGradient {
            switch self {
            case .accent:
                return AppActionGradient.primary
            case .warning:
                return LinearGradient(
                    colors: [Color(hex: 0xFFB13C), Color(hex: 0xE0830A)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .danger:
                return LinearGradient(
                    colors: [Color(hex: 0xFF5E5E), Color(hex: 0xE03434)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }

        var glowColor: Color {
            switch self {
            case .accent: return Color(hex: 0x0060EA).opacity(0.45)
            case .warning: return Color(hex: 0xE0830A).opacity(0.40)
            case .danger: return Color(hex: 0xE03434).opacity(0.40)
            }
        }
    }

    var tone: Tone = .accent
    /// Default 220×56 to match the mockup; callers can override via .frame.
    var width: CGFloat = 220
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: width, height: height)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.gradient)
                    .opacity(configuration.isPressed ? 0.85 : 1.0)
            )
            .shadow(color: tone.glowColor, radius: 24, x: 0, y: 8)
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule(style: .continuous))
    }
}

struct AppHoverOverlayModifier: ViewModifier {
    @State private var isHovered = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.pcPrimary.opacity(isHovered ? 0.28 : 0), lineWidth: 1)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}
extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
    func appGlassPanel(
        cornerRadius: CGFloat = AppRadius.xl,
        strokeOpacity: Double = 0.72,
        shadowOpacity: Double = 0.08
    ) -> some View {
        modifier(AppGlassPanelModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity, shadowOpacity: shadowOpacity))
    }

    func appSectionLabel() -> some View {
        self
            .font(AppFont.labelCaps)
            .foregroundStyle(Color.pcTextMuted)
            .textCase(.uppercase)
            .tracking(0.7)
    }
    func appHoverOverlay(cornerRadius: CGFloat = AppRadius.md) -> some View {
        modifier(AppHoverOverlayModifier(cornerRadius: cornerRadius))
    }

}

// MARK: - Extensions

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}
