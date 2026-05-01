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
}

// MARK: - Typography

struct AppFont {
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let heading = Font.system(size: 20, weight: .semibold, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .medium, design: .default)
    static let monospace = Font.system(size: 14, weight: .medium, design: .monospaced)
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
