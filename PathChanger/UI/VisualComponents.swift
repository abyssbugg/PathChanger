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
                .frame(width: 6, height: 6)

            if let icon {
                Image(systemName: icon)
                    .font(AppFont.metadata)
                    .foregroundStyle(color.opacity(0.92))
            }

            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.pcText)
                .textCase(.uppercase)
                .tracking(0.6)

            if let detail {
                Divider()
                    .frame(height: 12)
                    .background(Color.pcOutline.opacity(0.65))

                Text(detail)
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: 28)
        .background(Color.pcSurface.opacity(AppSurfaceAlpha.panel), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
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
                        .frame(width: 16)
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
                                .frame(height: 22)
                                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .appSectionLabel()

            HStack(spacing: AppSpacing.sm) {
                if let prefix {
                    Text(prefix)
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                        .frame(width: 34, alignment: .leading)
                }

                content
                    .font(AppFont.monospace)
                    .foregroundStyle(Color.pcText)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: 32)
            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .stroke(isFocused ? Color.pcAccent.opacity(0.6) : Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
            )
        }
    }
}

