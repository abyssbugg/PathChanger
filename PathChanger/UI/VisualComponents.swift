//
//  VisualComponents.swift
//  PathChanger
//
//  Shared reference-inspired visual components backed by the app design system
//

import SwiftUI

struct PCStatusChip: View {
    let title: String
    var icon: String? = nil
    var color: Color = .pcSecondary
    var detail: String? = nil

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.45), radius: 6)

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }

            Text(title)
                .font(AppFont.monoSmall)
                .foregroundStyle(Color.pcText)
                .textCase(.uppercase)
                .tracking(1.6)

            if let detail {
                Divider()
                    .frame(height: 12)
                    .background(Color.white.opacity(0.16))

                Text(detail)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(Color.pcTextMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.pcSurface.opacity(0.72), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.22), lineWidth: 1)
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
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Color.pcPrimary)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(title)
                            .font(AppFont.subheading)
                            .foregroundStyle(Color.pcText)

                        if let badge {
                            Text(badge)
                                .font(AppFont.monoSmall)
                                .foregroundStyle(Color.pcPrimary)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.pcPrimary.opacity(0.1), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.pcPrimary.opacity(0.22), lineWidth: 1)
                                )
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.caption)
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .appSectionLabel()

            HStack(spacing: AppSpacing.sm) {
                if let prefix {
                    Text(prefix)
                        .font(AppFont.monoSmall)
                        .foregroundStyle(Color.pcPrimary)
                        .frame(width: 34, alignment: .leading)
                }

                content
                    .font(AppFont.monospace)
                    .foregroundStyle(Color.pcText)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(Color.pcSurfaceHigh.opacity(0.78), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

