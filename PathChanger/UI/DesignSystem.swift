//
//  DesignSystem.swift
//  PathChanger
//
//  Organic design tokens from the pth mock.
//

import SwiftUI
import AppKit
import CoreText

enum Organic {
    static let bg = Color(hex: 0xF5EAD8)
    static let surface = Color(hex: 0xEBDDC5)
    static let text = Color(hex: 0x201E1D)

    static let neutral100 = Color(hex: 0xF9F4ED)
    static let neutral200 = Color(hex: 0xEEE7DB)
    static let neutral300 = Color(hex: 0xDCD3C4)
    static let neutral400 = Color(hex: 0xC0B6A5)
    static let neutral500 = Color(hex: 0xA19786)
    static let neutral600 = Color(hex: 0x82796A)
    static let neutral700 = Color(hex: 0x645C50)
    static let neutral800 = Color(hex: 0x474238)
    static let neutral900 = Color(hex: 0x2E2B25)

    static let accent = Color(hex: 0xC67139)
    static let accent100 = Color(hex: 0xFFF2EB)
    static let accent200 = Color(hex: 0xFFE1D0)
    static let accent300 = Color(hex: 0xFFC6A5)
    static let accent400 = Color(hex: 0xF6A06B)
    static let accent500 = Color(hex: 0xD67F48)
    static let accent600 = Color(hex: 0xB2622D)
    static let accent700 = Color(hex: 0x8C491A)
    static let accent800 = Color(hex: 0x643312)
    static let accent900 = Color(hex: 0x402310)

    static let sage = Color(hex: 0x7A8A5E)
    static let sage100 = Color(hex: 0xF0FAE1)
    static let sage200 = Color(hex: 0xE1EECC)
    static let sage300 = Color(hex: 0xCCDBB2)
    static let sage600 = Color(hex: 0x728157)
    static let sage700 = Color(hex: 0x56633F)
    static let sage800 = Color(hex: 0x3D472B)
    static let sage900 = Color(hex: 0x272E1B)

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 16
    static let radiusLG: CGFloat = 28

    static let headingName = "Caprasimo"
    static let bodyName = "Figtree"

    static func heading(_ size: CGFloat) -> Font {
        .custom(headingName, size: size)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(bodyName, size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func registerFonts() {
        let names = ["Caprasimo-Regular.ttf", "Figtree-Variable.ttf"]
        for name in names {
            let urls = [
                Bundle.main.url(forResource: name, withExtension: nil),
                Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: (name as NSString).pathExtension),
                Bundle.main.resourceURL?.appendingPathComponent("Fonts/\(name)"),
                Bundle.main.resourceURL?.appendingPathComponent(name)
            ]
            for url in urls.compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                break
            }
        }
    }
}

extension Color {
    static let appPrimary = Organic.accent
    static let appSecondary = Organic.sage
    static let appBackground = Organic.bg
    static let appSurface = Organic.surface
    static let modernBlue = Organic.accent
    static let modernPurple = Organic.accent600
    static let modernDarkSurface = Organic.surface
    static let modernDarkBackground = Organic.bg
}

struct AppFont {
    static let title = Organic.heading(28)
    static let heading = Organic.body(20, weight: .semibold)
    static let body = Organic.body(15)
    static let caption = Organic.body(12, weight: .medium)
    static let monospace = Organic.mono(14)
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Organic.neutral100)
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                    .stroke(Organic.neutral300, lineWidth: 1)
            )
            .shadow(color: Organic.neutral900.opacity(0.12), radius: 10, y: 3)
    }
}

struct PrimaryButtonModifier: ViewModifier {
    var isDisabled: Bool = false

    func body(content: Content) -> some View {
        content
            .font(Organic.body(12.5, weight: .bold))
            .foregroundStyle(Organic.neutral100)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(isDisabled ? Organic.neutral400 : Organic.accent600)
            .clipShape(Capsule())
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
