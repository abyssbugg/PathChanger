//
//  SidebarToggleButton.swift
//  PathChanger
//
//  Floating 40×40 glass button shown at top-left when the new map shell's
//  sidebar is collapsed. Tapping it (or pressing ⌘\) re-opens the sidebar.
//

import SwiftUI

struct SidebarToggleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.leading")
                .font(DS.Typography.headline)
                .foregroundStyle(Color.pcTextDynamic)
                .frame(width: DS.Metrics.sidebarToggleSize, height: DS.Metrics.sidebarToggleSize)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Metrics.sidebarToggleCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Metrics.sidebarToggleCornerRadius, style: .continuous)
                        .stroke(Color.pcOutlineDynamic, lineWidth: DS.Metrics.strokeWidth)
                )
                .shadow(
                    color: DS.Color.shadow.opacity(DS.Opacity.sidebarToggleShadow),
                    radius: DS.Metrics.sidebarToggleShadowRadius,
                    x: DS.Metrics.zero,
                    y: DS.Metrics.sidebarToggleShadowYOffset
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Metrics.sidebarToggleCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show sidebar")
        .accessibilityHint("Re-opens the navigation sidebar")
        .accessibilityIdentifier("mapShellSidebarToggle")
    }
}

#if DEBUG
struct SidebarToggleButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(DS.Opacity.previewDim)
            SidebarToggleButton(action: {})
        }
        .frame(width: DS.Metrics.previewSmallWidth, height: DS.Metrics.previewSmallHeight)
    }
}
#endif
