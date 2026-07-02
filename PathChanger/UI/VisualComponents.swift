//
//  VisualComponents.swift
//  PathChanger
//
//  Shared visual components backed by the app design system
//

import SwiftUI

struct PCStatusChip: View {
    let title: String
    var icon: String? = nil
    var color: Color = .pcSecondary
    var detail: String? = nil

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(color)
                .frame(width: DS.Metrics.statusChipDotSize, height: DS.Metrics.statusChipDotSize)

            if let icon {
                Image(systemName: icon)
                    .font(AppFont.metadata)
                    .foregroundStyle(color.opacity(DS.Opacity.panel))
            }

            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.pcText)
                .textCase(.uppercase)
                .tracking(DS.Metrics.labelTrackingTight)

            if let detail {
                Divider()
                    .frame(height: DS.Metrics.sidebarToggleCornerRadius)
                    .background(Color.pcOutline.opacity(DS.Opacity.subtleDivider))

                Text(detail)
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: DS.Metrics.mapRoutePanelButtonSize)
        .background(Color.pcSurface.opacity(AppSurfaceAlpha.panel), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
        )
    }
}

struct PCSectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(AppFont.label)
                        .foregroundStyle(Color.pcTextMuted)
                        .frame(width: AppSpacing.sm)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(title)
                            .font(AppFont.title)
                            .foregroundStyle(Color.pcText)

                        if let badge {
                            Text(badge)
                                .font(AppFont.metadata)
                                .foregroundStyle(Color.pcTextMuted)
                                .padding(.horizontal, AppSpacing.sm)
                                .frame(height: DS.Metrics.mapRouteCounterHeight)
                                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
                                )
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.metadata)
                            .foregroundStyle(Color.pcTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            content
        }
        .padding(AppSpacing.lg)
        .appGlassPanel(cornerRadius: AppRadius.xl)
    }
}

struct PCFieldShell<Content: View>: View {
    let label: String
    var prefix: String? = nil
    var isFocused: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        // Operational refinement: tighten caption-to-field gap (xxs vs xs),
        // slim the input row (28pt vs 32pt) and narrow the prefix slot so the
        // double-labelling (LATITUDE / Lat …) no longer dominates vertical
        // rhythm in the Teleport inspector.
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .appSectionLabel()

            HStack(spacing: AppSpacing.xs) {
                if let prefix {
                    Text(prefix)
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                        .frame(width: DS.Metrics.mapRoutePanelButtonSize, alignment: .leading)
                }

                content
                    .font(AppFont.monospace)
                    .foregroundStyle(Color.pcText)
            }
            .padding(.horizontal, AppSpacing.sm)
            .frame(minHeight: DS.Metrics.mapRoutePanelButtonSize)
            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .stroke(
                        isFocused ? Color.pcAccent.opacity(DS.Opacity.focusStroke) : Color.pcOutline.opacity(AppSurfaceAlpha.outline),
                        lineWidth: DS.Metrics.strokeWidth
                    )
            )
        }
    }
}

