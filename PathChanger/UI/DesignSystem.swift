//
//  DesignSystem.swift
//  PathChanger
//
//  Centralized design system and compatibility bridges.
//

import SwiftUI
import AppKit

struct DS {
    struct Color {
        // Backgrounds
        static let backgroundPrimary: SwiftUI.Color = .dynamic(
            light: NSColor(srgbRed: 0.97, green: 0.98, blue: 0.99, alpha: 1.0),
            dark: NSColor(srgbRed: 0.04, green: 0.08, blue: 0.15, alpha: 1.0)
        )
        static let backgroundSecondary: SwiftUI.Color = .dynamic(
            light: NSColor(srgbRed: 0.94, green: 0.96, blue: 0.98, alpha: 1.0),
            dark: NSColor(srgbRed: 0.08, green: 0.11, blue: 0.18, alpha: 1.0)
        )
        static let backgroundElevated: SwiftUI.Color = .dynamic(
            light: NSColor(srgbRed: 0.98, green: 0.985, blue: 0.995, alpha: 1.0),
            dark: NSColor(srgbRed: 0.11, green: 0.14, blue: 0.21, alpha: 1.0)
        )

        // Foregrounds
        static let foregroundPrimary: SwiftUI.Color = .dynamic(
            light: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0),
            dark: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.98, alpha: 1.0)
        )
        static let foregroundSecondary: SwiftUI.Color = foregroundPrimary.opacity(0.6)
        static let foregroundTertiary: SwiftUI.Color = foregroundPrimary.opacity(0.4)

        // Interactive
        static let accent: SwiftUI.Color = SwiftUI.Color(hex: 0x007AFF)
        static let accentHover: SwiftUI.Color = SwiftUI.Color(hex: 0x198BFF)
        static let accentPressed: SwiftUI.Color = SwiftUI.Color(hex: 0x005FD1)

        // Semantic
        static let destructive: SwiftUI.Color = SwiftUI.Color(hex: 0xFF5E5E)
        static let success: SwiftUI.Color = SwiftUI.Color(hex: 0x4EDEA3)
        static let warning: SwiftUI.Color = SwiftUI.Color(hex: 0xFFB786)
        static let inactive: SwiftUI.Color = .dynamic(
            light: NSColor(srgbRed: 0.75, green: 0.78, blue: 0.84, alpha: 1.0),
            dark: NSColor(srgbRed: 0.38, green: 0.42, blue: 0.48, alpha: 1.0)
        )
        static let shadow: SwiftUI.Color = .black
        static let markerStroke: SwiftUI.Color = .white

        // Mockup-aligned semantic accents (geospoofer-pro.html palette)
        // These are the exact hex values from the mockup's `:root` CSS variables,
        // provided as a discrete namespace so SwiftUI controls can match the
        // HTML spec 1:1 without disturbing the legacy semantic tokens above.
        static let mockupEmerald: SwiftUI.Color = SwiftUI.Color(hex: 0x34D399)
        static let mockupAmber: SwiftUI.Color   = SwiftUI.Color(hex: 0xFBBF24)
        static let mockupRed: SwiftUI.Color     = SwiftUI.Color(hex: 0xF87171)
        static let mockupSky: SwiftUI.Color     = SwiftUI.Color(hex: 0x38BDF8)
        static let mockupViolet: SwiftUI.Color  = SwiftUI.Color(hex: 0x7C6CF6)
    }

    // MARK: - Per-mode accent system
    // Mirrors the mockup's `[data-mode]` CSS custom properties 1:1.
    // Teleport = violet, Multi-Spot = sky, Joystick = orange.
    // Each mode carries: base, base2 (gradient stop), soft tint, glow, line, line-strong.
    struct ModeAccent {
        let base: SwiftUI.Color
        let base2: SwiftUI.Color
        let soft: SwiftUI.Color      // ~14% opacity tint background
        let glow: SwiftUI.Color      // ~45% opacity for shadows/halos
        let line: SwiftUI.Color      // ~30% opacity for subtle borders
        let lineStrong: SwiftUI.Color // ~50% opacity for active borders

        /// Linear gradient from base to base2 (top -> bottom), matching the mockup's button gradients.
        var gradient: LinearGradient {
            LinearGradient(colors: [base, base2], startPoint: .top, endPoint: .bottom)
        }

        static let teleport = ModeAccent(
            base: SwiftUI.Color(hex: 0x7C6CF6),
            base2: SwiftUI.Color(hex: 0x635BFF),
            soft: SwiftUI.Color(hex: 0x7C6CF6, alpha: 0.14),
            glow: SwiftUI.Color(hex: 0x7C6CF6, alpha: 0.45),
            line: SwiftUI.Color(hex: 0x7C6CF6, alpha: 0.30),
            lineStrong: SwiftUI.Color(hex: 0x7C6CF6, alpha: 0.50)
        )

        static let multiSpot = ModeAccent(
            base: SwiftUI.Color(hex: 0x38BDF8),
            base2: SwiftUI.Color(hex: 0x0EA5E9),
            soft: SwiftUI.Color(hex: 0x38BDF8, alpha: 0.14),
            glow: SwiftUI.Color(hex: 0x38BDF8, alpha: 0.45),
            line: SwiftUI.Color(hex: 0x38BDF8, alpha: 0.30),
            lineStrong: SwiftUI.Color(hex: 0x38BDF8, alpha: 0.50)
        )

        static let joystick = ModeAccent(
            base: SwiftUI.Color(hex: 0xFB923C),
            base2: SwiftUI.Color(hex: 0xF97316),
            soft: SwiftUI.Color(hex: 0xFB923C, alpha: 0.14),
            glow: SwiftUI.Color(hex: 0xFB923C, alpha: 0.45),
            line: SwiftUI.Color(hex: 0xFB923C, alpha: 0.30),
            lineStrong: SwiftUI.Color(hex: 0xFB923C, alpha: 0.50)
        )

        /// Resolve the accent for a given AppMode. Settings falls back to the global accent.
        static func forMode(_ mode: AppMode) -> ModeAccent {
            switch mode {
            case .teleport:  return .teleport
            case .route:     return .multiSpot
            case .joystick:  return .joystick
            case .settings:  return .teleport
            }
        }
    }

    struct Radius {
        static let panel: CGFloat = 16
        static let pill: CGFloat = 14
        static let button: CGFloat = 10
        static let chip: CGFloat = 8

        // Mockup-aligned radii (geospoofer-pro.html `:root` --r-* tokens)
        static let sm: CGFloat = 8    // --r-sm
        static let md: CGFloat = 11   // --r-md
        static let lg: CGFloat = 14   // --r-lg
        static let xl: CGFloat = 18   // --r-xl
    }

    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 16
        static let md: CGFloat = 24
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
        static let xxl: CGFloat = 64
    }

    struct Typography {
        static let labelPrimary: Font = .system(size: 13, weight: .medium, design: .default)
        static let labelSecondary: Font = .system(size: 13, weight: .regular, design: .default)
        static let caption: Font = .system(size: 12, weight: .regular, design: .default)
        static let headline: Font = .system(size: 16, weight: .semibold, design: .default)
        static let title: Font = .system(size: 18, weight: .semibold, design: .default)
        static let subheadline: Font = .system(size: 14, weight: .semibold, design: .default)
        static let metadata: Font = .system(size: 12, weight: .regular, design: .default)
        static let monospace: Font = .system(size: 13, weight: .regular, design: .monospaced)
        static let monoSmall: Font = .system(size: 12, weight: .regular, design: .monospaced)
        static let labelCaps: Font = .system(size: 12, weight: .medium, design: .default)
        static let iconLarge: Font = .system(size: DS.Metrics.largeIconSize, weight: .regular, design: .default)
        static let iconXLarge: Font = .system(size: DS.Metrics.onboardingCompletionIconSize, weight: .regular, design: .default)
    }

    struct Animation {
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.2)
        static let fast: SwiftUI.Animation = .easeOut(duration: 0.12)
        static let slow: SwiftUI.Animation = .spring(response: 0.32, dampingFraction: 0.85)
    }

    struct Metrics {
        static let zero: CGFloat = 0
        static let one: CGFloat = 1
        static let two: CGFloat = 2
        static let unitScale: CGFloat = 1
        static let minButtonHeight: CGFloat = 32
        static let primaryPillWidth: CGFloat = 256
        static let primaryPillHeight: CGFloat = 64
        static let primaryPillHoverScale: CGFloat = 1.02
        static let primaryPillPressedScale: CGFloat = 0.97
        static let primaryPillShadowRadius: CGFloat = 16
        static let primaryPillShadowYOffset: CGFloat = 8
        static let devicePillWidth: CGFloat = 248
        static let devicePillHeight: CGFloat = 48
        static let deviceAvatarSize: CGFloat = 24
        static let statusDotSize: CGFloat = 8
        static let statusChipDotSize: CGFloat = 6
        static let popoverWidth: CGFloat = 320
        static let sidebarWidth: CGFloat = 240
        static let sidebarTopGutterHeight: CGFloat = 56
        static let sidebarControlHeight: CGFloat = 32
        static let sidebarSearchDropdownTopInset: CGFloat = 108
        static let sidebarCollapseButtonSize: CGFloat = 32
        static let subordinatePillShadowRadius: CGFloat = 8
        static let subordinatePillShadowYOffset: CGFloat = 4
        static let subordinatePillHoverScale: CGFloat = 1.01
        static let subordinatePillPressedScale: CGFloat = 0.99
        static let strokeWidth: CGFloat = 1
        static let mapMarkerHaloSize: CGFloat = 48
        static let mapMarkerCoreSize: CGFloat = 16
        static let mapMarkerStrokeWidth: CGFloat = 3
        static let mapMarkerShadowRadius: CGFloat = 2
        static let mapContextMenuMaxOffset: CGFloat = 520
        static let mapToolbarSearchMinHeight: CGFloat = 36
        static let mapToolbarDividerHeight: CGFloat = 28
        static let mapToolbarLocateButtonSize: CGFloat = 32
        static let mapToolbarSearchMinWidth: CGFloat = 260
        static let mapToolbarSearchIdealWidth: CGFloat = 360
        static let mapToolbarSearchMaxWidth: CGFloat = 420
        static let mapSearchResultsShadowRadius: CGFloat = 4
        static let mapSearchResultsShadowYOffset: CGFloat = 2
        static let mapRoutePanelButtonSize: CGFloat = 28
        static let mapRouteCounterHeight: CGFloat = 22
        static let mapRouteListMaxHeight: CGFloat = 132
        static let mapTeleportPanelMinWidth: CGFloat = 260
        static let mapTeleportPanelIdealWidth: CGFloat = 296
        static let mapTeleportPanelMaxWidth: CGFloat = 312
        static let mapRoutePanelMinWidth: CGFloat = 280
        static let mapRoutePanelIdealWidth: CGFloat = 312
        static let mapRoutePanelMaxWidth: CGFloat = 332
        static let settingsContentMaxWidth: CGFloat = 760
        static let settingsPickerWidth: CGFloat = 150
        static let settingsStatusDotSize: CGFloat = 8
        static let settingsTunnelSpinnerScale: CGFloat = 0.75
        static let settingsListIconFontSize: CGFloat = 18
        static let settingsListIconWidth: CGFloat = 28
        static let settingsProbeSpinnerScale: CGFloat = 0.70
        static let settingsPairSpinnerScale: CGFloat = 0.65
        static let settingsLogMaxHeight: CGFloat = 160
        static let shortcutLabelTracking: CGFloat = 0.7
        static let shortcutKeyWidth: CGFloat = 80
        static let largeIconSize: CGFloat = 48
        static let onboardingCompletionIconSize: CGFloat = 80
        static let dialogWidth: CGFloat = 400
        static let onboardingHorizontalPadding: CGFloat = 40
        static let onboardingHeaderTopPadding: CGFloat = 30
        static let onboardingToastBottomInset: CGFloat = 100
        static let onboardingMinWidth: CGFloat = 560
        static let onboardingIdealWidth: CGFloat = 700
        static let onboardingMaxWidth: CGFloat = 820
        static let onboardingMinHeight: CGFloat = 480
        static let onboardingIdealHeight: CGFloat = 550
        static let onboardingMaxHeight: CGFloat = 720
        static let onboardingProgressScale: CGFloat = 1.2
        static let contentMinWidth: CGFloat = 760
        static let contentIdealWidth: CGFloat = 1000
        static let contentMinHeight: CGFloat = 560
        static let contentIdealHeight: CGFloat = 700
        static let shellSidebarToggleLeadingInset: CGFloat = 16
        static let shellSidebarToggleTopInset: CGFloat = 56
        static let shellFloatingInset: CGFloat = 24
        static let shellPrimaryPillBottomInset: CGFloat = 28
        static let shellHiddenShortcutSize: CGFloat = 1
        static let settingsSheetHeight: CGFloat = 620
        static let shellPreviewWidth: CGFloat = 1100
        static let shellPreviewHeight: CGFloat = 720
        static let sidebarToggleSize: CGFloat = 40
        static let sidebarToggleIconSize: CGFloat = 16
        static let sidebarToggleCornerRadius: CGFloat = 12
        static let sidebarToggleShadowRadius: CGFloat = 12
        static let sidebarToggleShadowYOffset: CGFloat = 4
        static let previewSmallWidth: CGFloat = 200
        static let previewSmallHeight: CGFloat = 120
        static let diagnosticsMinWidth: CGFloat = 500
        static let diagnosticsMinHeight: CGFloat = 400
        static let diagnosticsSheetMinWidth: CGFloat = 600
        static let diagnosticsSheetMinHeight: CGFloat = 500
        static let toastShadowRadius: CGFloat = 6
        static let toastShadowYOffset: CGFloat = 3
        static let toastHiddenScale: CGFloat = 0.8
        static let toastContainerMaxWidth: CGFloat = 500
        static let toastPreviewWidth: CGFloat = 600
        static let toastPreviewHeight: CGFloat = 400
        static let dependencyHeaderIconSize: CGFloat = 48
        static let dependencyTopPadding: CGFloat = 32
        static let dependencyCardPadding: CGFloat = 16
        static let dependencyActionVPadding: CGFloat = 8
        static let dependencyActionHPadding: CGFloat = 12
        static let dependencyRetryButtonVPadding: CGFloat = 10
        static let dependencyMaxWidth: CGFloat = 760
        static let dependencyMinWidth: CGFloat = 560
        static let dependencyIdealWidth: CGFloat = 800
        static let dependencyMinHeight: CGFloat = 480
        static let dependencyIdealHeight: CGFloat = 600
        static let featureRowIconWidth: CGFloat = 30
        static let setupStepCircleSize: CGFloat = 32
        static let stepIndicatorSize: CGFloat = 8
        static let quickTipIconWidth: CGFloat = 24
        static let sheetStepBadgeSize: CGFloat = 20
        static let smallCornerRadius: CGFloat = 4
        static let labelTrackingTight: CGFloat = 0.6
        static let joystickOuterRadius: CGFloat = 56
        static let joystickInnerRadius: CGFloat = 18
        static let joystickDirectionInset: CGFloat = 13
        static let joystickOuterRingScale: CGFloat = 1.45
        static let joystickInnerRingScale: CGFloat = 0.82
        static let joystickReleaseSpringResponse: CGFloat = 0.3
        static let joystickReleaseSpringDamping: CGFloat = 0.6
    }

    struct Opacity {
        static let idleRow: Double = 0.16
        static let hoverRow: Double = 0.22
        static let selectedRow: Double = 0.28
        static let activeRow: Double = 0.40
        static let inputField: Double = 0.72
        static let panel: Double = 0.94
        static let divider: Double = 0.45
        static let outline: Double = 0.55
        static let disabled: Double = 0.55
        static let selectionTint: Double = 0.10
        static let mapMarkerHalo: Double = 0.14
        static let mapMarkerShadow: Double = 0.12
        static let focusStroke: Double = 0.60
        static let toolbarPanelStroke: Double = 0.18
        static let toolbarPanelShadow: Double = 0.12
        static let searchResultsSurface: Double = 0.98
        static let searchResultsShadow: Double = 0.08
        static let warningTint: Double = 0.10
        static let warningBannerTint: Double = 0.12
        static let subtleDivider: Double = 0.65
        static let previewDim: Double = 0.2
        static let sidebarToggleShadow: Double = 0.18
        static let toastShadow: Double = 0.12
        static let progressIndicatorFill: Double = 0.3
        static let warningPanelTint: Double = 0.12
    }
}

// MARK: - Backward compatibility tokens (bridged to DS)

extension Color {
    static let appPrimary = DS.Color.accent
    static let appSecondary = DS.Color.success
    static let appBackground = DS.Color.backgroundPrimary
    static let appSurface = DS.Color.backgroundSecondary

    static let modernBlue = DS.Color.accent
    static let modernPurple = SwiftUI.Color(hex: 0x5856D6)
    static let modernDarkSurface = DS.Color.backgroundSecondary
    static let modernDarkBackground = DS.Color.backgroundPrimary

    static let pcBackground = DS.Color.backgroundPrimary
    static let pcSurface = DS.Color.backgroundSecondary
    static let pcSurfaceHigh = DS.Color.backgroundElevated
    static let pcSurfaceHighest = DS.Color.backgroundElevated
    static let pcPrimary = DS.Color.foregroundPrimary
    static let pcAccent = DS.Color.accent
    static let pcSecondary = DS.Color.success
    static let pcWarning = DS.Color.warning
    static let pcDanger = DS.Color.destructive
    static let pcText = DS.Color.foregroundPrimary
    static let pcTextMuted = DS.Color.foregroundSecondary
    static let pcOutline = DS.Color.foregroundTertiary

    static let pcTextDynamic = DS.Color.foregroundPrimary
    static let pcTextMutedDynamic = DS.Color.foregroundSecondary
    static let pcOutlineDynamic = DS.Color.foregroundTertiary
    static let pcSurfaceTintDynamic = DS.Color.backgroundElevated.opacity(0.55)
    static let pcSystemBlue = DS.Color.accent
    static let pcSystemIndigo = SwiftUI.Color(hex: 0x5856D6)
}

// MARK: - Action gradient + shadow constants

enum AppActionGradient {
    static let primary = LinearGradient(
        colors: [DS.Color.accentHover, DS.Color.accentPressed],
        startPoint: .top,
        endPoint: .bottom
    )

    static let avatar = LinearGradient(
        colors: [DS.Color.accent, Color.pcSystemIndigo],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography/spacing/radius bridges

struct AppFont {
    static let title = DS.Typography.title
    static let heading = DS.Typography.headline
    static let subheading = DS.Typography.subheadline
    static let label = DS.Typography.labelPrimary
    static let body = DS.Typography.labelSecondary
    static let caption = DS.Typography.caption
    static let metadata = DS.Typography.metadata
    static let monospace = DS.Typography.monospace
    static let monoSmall = DS.Typography.monoSmall
    static let labelCaps = DS.Typography.labelCaps
}

enum AppSpacing {
    static let xxs: CGFloat = DS.Spacing.xxs
    static let xs: CGFloat = DS.Spacing.xs
    static let sm: CGFloat = DS.Spacing.sm
    static let md: CGFloat = DS.Spacing.md
    static let lg: CGFloat = DS.Spacing.lg
    static let xl: CGFloat = DS.Spacing.xl
    static let xxl: CGFloat = DS.Spacing.xxl
}

enum AppRadius {
    static let sm: CGFloat = DS.Radius.chip
    static let md: CGFloat = DS.Radius.button
    static let lg: CGFloat = DS.Radius.button
    static let xl: CGFloat = DS.Radius.panel
    static let xxl: CGFloat = DS.Radius.panel
}

enum AppSurfaceAlpha {
    static let idleRow: Double = DS.Opacity.idleRow
    static let hoverRow: Double = DS.Opacity.hoverRow
    static let selectedRow: Double = DS.Opacity.selectedRow
    static let activeRow: Double = DS.Opacity.activeRow
    static let inputField: Double = DS.Opacity.inputField
    static let panel: Double = DS.Opacity.panel
    static let divider: Double = DS.Opacity.divider
    static let outline: Double = DS.Opacity.outline
}

// MARK: - Modifiers

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.sm)
            .background(DS.Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: DS.Spacing.xs, x: 0, y: DS.Spacing.xxs)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                    .stroke(DS.Color.foregroundTertiary.opacity(0.65), lineWidth: DS.Metrics.strokeWidth)
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
                    .fill(DS.Color.backgroundElevated.opacity(DS.Opacity.panel))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.Color.foregroundTertiary.opacity(strokeOpacity), lineWidth: DS.Metrics.strokeWidth)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: DS.Spacing.xs, x: 0, y: DS.Spacing.xxs)
    }
}

struct AppCapsuleButtonStyle: ButtonStyle {
    var accent: Color = DS.Color.accent
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.labelPrimary)
            .foregroundStyle(isProminent ? DS.Color.foregroundPrimary : accent)
            .padding(.horizontal, DS.Spacing.sm)
            .frame(minHeight: DS.Metrics.minButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .fill(isProminent ? accent.opacity(configuration.isPressed ? 0.78 : 0.92) : accent.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .stroke(accent.opacity(isProminent ? 0.22 : 0.24), lineWidth: DS.Metrics.strokeWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .animation(DS.Animation.fast, value: configuration.isPressed)
    }
}

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
                    colors: [DS.Color.warning, DS.Color.warning.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .danger:
                return LinearGradient(
                    colors: [DS.Color.destructive, DS.Color.destructive.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }

        var glowColor: Color {
            switch self {
            case .accent: return DS.Color.accentPressed.opacity(0.45)
            case .warning: return DS.Color.warning.opacity(0.40)
            case .danger: return DS.Color.destructive.opacity(0.40)
            }
        }
    }

    var tone: Tone = .accent
    var width: CGFloat = DS.Metrics.primaryPillWidth
    var height: CGFloat = DS.Metrics.primaryPillHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.headline)
            .foregroundStyle(DS.Color.foregroundPrimary)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .fill(tone.gradient)
                    .opacity(configuration.isPressed ? 0.9 : 1.0)
            )
            .shadow(color: tone.glowColor, radius: DS.Spacing.md, x: 0, y: DS.Spacing.xs)
            .shadow(color: .black.opacity(0.18), radius: DS.Spacing.xs, x: 0, y: DS.Spacing.xxs)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(DS.Animation.fast, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous))
    }
}

struct AppHoverOverlayModifier: ViewModifier {
    @State private var isHovered = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.Color.accent.opacity(isHovered ? 0.28 : 0), lineWidth: DS.Metrics.strokeWidth)
            )
            .onHover { hovering in
                withAnimation(DS.Animation.fast) {
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
        cornerRadius: CGFloat = DS.Radius.panel,
        strokeOpacity: Double = 0.72,
        shadowOpacity: Double = 0.08
    ) -> some View {
        modifier(AppGlassPanelModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity, shadowOpacity: shadowOpacity))
    }

    func appSectionLabel() -> some View {
        self
            .font(DS.Typography.labelCaps)
            .foregroundStyle(DS.Color.foregroundTertiary)
            .textCase(.uppercase)
            .tracking(0.7)
    }

    func appHoverOverlay(cornerRadius: CGFloat = DS.Radius.button) -> some View {
        modifier(AppHoverOverlayModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Extensions

extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]) {
            case .darkAqua, .vibrantDark:
                return dark
            default:
                return light
            }
        }))
    }

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
