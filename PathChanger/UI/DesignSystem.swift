//
//  DesignSystem.swift
//  PathChanger
//
//  Organic design tokens from the pth mock.
//

import SwiftUI
import AppKit
import CoreText

enum OrganicAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    static func persisted(_ rawValue: String?) -> OrganicAppearance {
        rawValue.flatMap(OrganicAppearance.init(rawValue:)) ?? .light
    }
}

enum Organic {
    static let bg = Color(lightHex: 0xF5EAD8, darkHex: 0x1A1714)
    static let surface = Color(lightHex: 0xEBDDC5, darkHex: 0x241F1B)
    static let text = Color(lightHex: 0x201E1D, darkHex: 0xF5EAD8)

    static let neutral100 = Color(lightHex: 0xF9F4ED, darkHex: 0x241F1B)
    static let neutral200 = Color(lightHex: 0xEEE7DB, darkHex: 0x2E2822)
    static let neutral300 = Color(lightHex: 0xDCD3C4, darkHex: 0x3D352D)
    static let neutral400 = Color(lightHex: 0xC0B6A5, darkHex: 0x544A3F)
    static let neutral500 = Color(lightHex: 0xA19786, darkHex: 0x6F6455)
    static let neutral600 = Color(lightHex: 0x82796A, darkHex: 0x9C9081)
    static let neutral700 = Color(lightHex: 0x645C50, darkHex: 0xC0B4A2)
    static let neutral800 = Color(lightHex: 0x474238, darkHex: 0xDDD2C0)
    static let neutral900 = Color(lightHex: 0x2E2B25, darkHex: 0xF5EAD8)
    static let shadow = Color(lightHex: 0x2E2B25, darkHex: 0x000000)

    static let accent = Color(lightHex: 0xC67139, darkHex: 0xD8834F)
    static let accent100 = Color(lightHex: 0xFFF2EB, darkHex: 0x33231A)
    static let accent200 = Color(lightHex: 0xFFE1D0, darkHex: 0x482D1F)
    static let accent300 = Color(lightHex: 0xFFC6A5, darkHex: 0x6B4028)
    static let accent400 = Color(lightHex: 0xF6A06B, darkHex: 0x8C5330)
    static let accent500 = Color(lightHex: 0xD67F48, darkHex: 0xB2663A)
    static let accent600 = Color(lightHex: 0xB2622D, darkHex: 0xCD7B46)
    static let accent700 = Color(lightHex: 0x8C491A, darkHex: 0xE39A6D)
    static let accent800 = Color(lightHex: 0x643312, darkHex: 0xF0B995)
    static let accent900 = Color(lightHex: 0x402310, darkHex: 0xF8D6BD)

    static let sage = Color(lightHex: 0x7A8A5E, darkHex: 0x93A870)
    static let sage100 = Color(lightHex: 0xF0FAE1, darkHex: 0x232719)
    static let sage200 = Color(lightHex: 0xE1EECC, darkHex: 0x2D3320)
    static let sage300 = Color(lightHex: 0xCCDBB2, darkHex: 0x3F4A2C)
    static let sage400 = Color(lightHex: 0xAABD88, darkHex: 0x5B6B40)
    static let sage500 = Color(lightHex: 0x8FA36C, darkHex: 0x778A55)
    static let sage600 = Color(lightHex: 0x728157, darkHex: 0x93A870)
    static let sage700 = Color(lightHex: 0x56633F, darkHex: 0xB0C48C)
    static let sage800 = Color(lightHex: 0x3D472B, darkHex: 0xC9DBAA)
    static let sage900 = Color(lightHex: 0x272E1B, darkHex: 0xE1EECC)

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
            .shadow(color: Organic.shadow.opacity(0.12), radius: 10, y: 3)
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

    init(lightHex: UInt, darkHex: UInt) {
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? darkHex : lightHex)
        }
        self.init(nsColor: dynamic)
    }
}

private extension NSColor {
    convenience init(hex: UInt) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

enum OrganicGlyph {
    case phone
    case shieldCheck
    case sun
    case moon
    case settings
    case teleport
    case jump
    case twoSpot
    case multiSpot
    case joystick
}

/// Native rendering of the canonical mock's 24×24 stroked SVG glyphs.
struct OrganicGlyphView: View {
    let glyph: OrganicGlyph
    var size: CGFloat = 15
    var lineWidth: CGFloat = 2.75

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            let offset = CGPoint(
                x: (canvasSize.width - 24 * scale) / 2,
                y: (canvasSize.height - 24 * scale) / 2
            )
            let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
                CGPoint(x: offset.x + x * scale, y: offset.y + y * scale)
            }
            let rect: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect = { x, y, width, height in
                CGRect(x: offset.x + x * scale, y: offset.y + y * scale, width: width * scale, height: height * scale)
            }
            let stroke = StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round)
            func outline(_ path: Path) { context.stroke(path, with: .foreground, style: stroke) }
            func fill(_ path: Path) { context.fill(path, with: .foreground) }
            func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, filled: Bool = false) {
                let path = Path(ellipseIn: rect(x - radius, y - radius, radius * 2, radius * 2))
                if filled { fill(path) } else { outline(path) }
            }

            switch glyph {
            case .phone:
                var path = Path(roundedRect: rect(6.5, 2.5, 11, 19), cornerRadius: 2.8 * scale)
                path.move(to: point(10.6, 5.4)); path.addLine(to: point(13.4, 5.4)); outline(path)
            case .shieldCheck:
                var path = Path()
                path.move(to: point(12, 3)); path.addLine(to: point(5, 6)); path.addLine(to: point(5, 11))
                path.addCurve(to: point(12, 21), control1: point(5, 15.5), control2: point(8, 19))
                path.addCurve(to: point(19, 11), control1: point(16, 19), control2: point(19, 15.5))
                path.addLine(to: point(19, 6)); path.closeSubpath()
                path.move(to: point(9.5, 12)); path.addLine(to: point(11.3, 13.8)); path.addLine(to: point(15, 10)); outline(path)
            case .sun:
                circle(12, 12, 4)
                var path = Path()
                [(12,2,12,4),(12,20,12,22),(4.9,4.9,6.3,6.3),(17.7,17.7,19.1,19.1),
                 (2,12,4,12),(20,12,22,12),(4.9,19.1,6.3,17.7),(17.7,6.3,19.1,4.9)].forEach { a,b,c,d in
                    path.move(to: point(a,b)); path.addLine(to: point(c,d))
                }
                outline(path)
            case .moon:
                var path = Path()
                path.move(to: point(20, 14.5))
                path.addCurve(to: point(9.5, 4), control1: point(14.2, 15.4), control2: point(8.6, 9.8))
                path.addCurve(to: point(20, 14.5), control1: point(4.2, 7.7), control2: point(9.5, 22.8)); outline(path)
            case .settings:
                var path = Path()
                [(4,6,13,6),(17,6,20,6),(4,12,7,12),(11,12,20,12),(4,18,13,18),(17,18,20,18)].forEach { a,b,c,d in
                    path.move(to: point(a,b)); path.addLine(to: point(c,d))
                }
                outline(path); circle(15, 6, 2); circle(9, 12, 2); circle(15, 18, 2)
            case .teleport:
                circle(12, 12, 3.2); circle(12, 12, 7.4)
                var path = Path()
                [(12,1.6,12,4.8),(12,19.2,12,22.4),(1.6,12,4.8,12),(19.2,12,22.4,12)].forEach { a,b,c,d in
                    path.move(to: point(a,b)); path.addLine(to: point(c,d))
                }
                outline(path)
            case .jump:
                circle(12, 12, 2.1, filled: true)
                var path = Path()
                [(12,7.4,12,2.8),(12,2.8,9.8,5),(12,2.8,14.2,5),(12,16.6,12,21.2),
                 (12,21.2,9.8,19),(12,21.2,14.2,19),(7.4,12,2.8,12),(2.8,12,5,9.8),
                 (2.8,12,5,14.2),(16.6,12,21.2,12),(21.2,12,19,9.8),(21.2,12,19,14.2)].forEach { a,b,c,d in
                    path.move(to: point(a,b)); path.addLine(to: point(c,d))
                }
                outline(path)
            case .twoSpot:
                var path = Path()
                path.move(to: point(4.5, 7.5)); path.addLine(to: point(13.5, 7.5))
                path.addCurve(to: point(13.5, 13.5), control1: point(17.5, 7.5), control2: point(17.5, 13.5))
                path.addLine(to: point(8.5, 13.5))
                path.addCurve(to: point(8.5, 19.5), control1: point(4.5, 13.5), control2: point(4.5, 19.5))
                path.addLine(to: point(19.5, 19.5)); outline(path)
                circle(4.5, 7.5, 1.9, filled: true); circle(19.5, 19.5, 1.9, filled: true)
            case .multiSpot:
                var path = Path()
                path.move(to: point(4.5, 6)); path.addLine(to: point(14, 6)); path.addLine(to: point(14, 18)); path.addLine(to: point(19.5, 18)); outline(path)
                circle(4.5, 6, 2, filled: true); circle(14, 12, 2, filled: true); circle(19.5, 18, 2, filled: true)
            case .joystick:
                circle(12, 6.2, 3)
                var path = Path()
                path.move(to: point(12, 9.2)); path.addLine(to: point(12, 15.6))
                path.move(to: point(5.4, 20.4)); path.addCurve(to: point(18.6, 20.4), control1: point(5.4, 14), control2: point(18.6, 14)); outline(path)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
