//
//  FloatingControlPanel.swift
//  PathChanger
//
//  Reusable structured container for map controls
//

import SwiftUI

struct FloatingControlPanel<Content: View>: View {
    let title: String?
    let icon: String?
    /// Optional per-mode accent (mockup `.card-head .ci` icon chip).
    /// Nil keeps the legacy neutral header styling.
    let accent: Color?
    let content: Content

    init(title: String? = nil, icon: String? = nil, accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        // Operational refinement: tighter rhythm (md/md) instead of (lg/lg)
        // so mode panels feel denser without redesigning the container.
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let title = title {
                HStack(spacing: AppSpacing.sm) {
                    if let icon = icon {
                        if let accent {
                            // Mockup card-head icon chip: accent-tinted rounded square.
                            Image(systemName: icon)
                                .font(AppFont.label)
                                .foregroundStyle(accent)
                                .frame(width: DS.Metrics.iconButtonSize, height: DS.Metrics.iconButtonSize)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                        .fill(accent.opacity(DS.Opacity.statusTint))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                        .stroke(accent.opacity(DS.Opacity.statusBorder), lineWidth: DS.Metrics.strokeWidth)
                                )
                        } else {
                            Image(systemName: icon)
                                .font(AppFont.label)
                                .foregroundStyle(Color.pcTextMuted)
                        }
                    }
                    Text(title)
                        .font(AppFont.heading)
                        .foregroundStyle(Color.pcText)

                    Spacer()
                }
            }

            content
        }
        .padding(AppSpacing.md)
        .dsGlassSurface(cornerRadius: AppRadius.xl)
    }
}

struct PanelStateStrip: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color
    var accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppFont.metadata)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: DS.Metrics.one) {
                Text(title)
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcText)
                    .lineLimit(1)
                Text(detail)
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(color.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(color.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
#if DEBUG
struct FloatingControlPanel_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.pcBackground.ignoresSafeArea()

            FloatingControlPanel(title: "Teleport", icon: "mappin.and.ellipse") {
                VStack {
                    TextField("Latitude", text: .constant("35.6812"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Longitude", text: .constant("139.7671"))
                        .textFieldStyle(.roundedBorder)
                    Button("Teleport") {}
                        .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                }
                .frame(width: DS.Metrics.previewSmallWidth)
            }
        }
    }
}
#endif
