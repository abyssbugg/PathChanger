//
//  DesignSystem.swift
//  PathChanger
//
//  Centralized design system for the "Modern Pro" UI
//  Defines colors, typography, and common modifiers
//

import SwiftUI

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

    // Reference-inspired PathChanger palette
    static let pcBackground = Color(hex: 0x0B1326)
    static let pcSurface = Color(hex: 0x171F33)
    static let pcSurfaceHigh = Color(hex: 0x222A3D)
    static let pcSurfaceHighest = Color(hex: 0x2D3449)
    static let pcPrimary = Color(hex: 0xADC6FF)
    static let pcAccent = Color(hex: 0x3B82F6)
    static let pcSecondary = Color(hex: 0x4EDEA3)
    static let pcWarning = Color(hex: 0xFFB786)
    static let pcDanger = Color(hex: 0xFF6B7A)
    static let pcText = Color(hex: 0xDAE2FD)
    static let pcTextMuted = Color(hex: 0x8D97B3)
    static let pcOutline = Color(hex: 0x44506A)
}

// MARK: - Typography

struct AppFont {
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let heading = Font.system(size: 20, weight: .semibold, design: .default)
    static let subheading = Font.system(size: 16, weight: .semibold, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .medium, design: .default)
    static let monospace = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let labelCaps = Font.system(size: 11, weight: .bold, design: .default)
}

// MARK: - Spacing & Radius

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
    static let xxl: CGFloat = 28
}

// MARK: - Modifiers

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
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
                    .fill(Color.pcSurface.opacity(0.68))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strokeOpacity),
                                Color.pcPrimary.opacity(strokeOpacity * 0.45),
                                Color.black.opacity(strokeOpacity * 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
    }
}

struct AppCapsuleButtonStyle: ButtonStyle {
    var accent: Color = .pcAccent
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(isProminent ? Color.white : accent)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                Capsule()
                    .fill(isProminent ? accent.opacity(configuration.isPressed ? 0.75 : 1) : accent.opacity(configuration.isPressed ? 0.18 : 0.1))
            )
            .overlay(
                Capsule()
                    .stroke(accent.opacity(isProminent ? 0.2 : 0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PrimaryButtonModifier: ViewModifier {
    var isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(
                isDisabled ? Color.gray.opacity(0.3) : Color.blue
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: isDisabled ? .clear : .blue.opacity(0.4), radius: 8, x: 0, y: 4)
            .animation(.easeInOut, value: isDisabled)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
    func appGlassPanel(
        cornerRadius: CGFloat = AppRadius.xl,
        strokeOpacity: Double = 0.16,
        shadowOpacity: Double = 0.22
    ) -> some View {
        modifier(AppGlassPanelModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity, shadowOpacity: shadowOpacity))
    }

    func appSectionLabel() -> some View {
        self
            .font(AppFont.labelCaps)
            .foregroundStyle(Color.pcTextMuted)
            .textCase(.uppercase)
            .tracking(1.8)
    }

    func primaryButtonStyle(isDisabled: Bool = false) -> some View {
        modifier(PrimaryButtonModifier(isDisabled: isDisabled))
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
