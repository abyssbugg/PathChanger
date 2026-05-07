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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.pcTextDynamic)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.pcOutlineDynamic, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Color.gray.opacity(0.2)
            SidebarToggleButton(action: {})
        }
        .frame(width: 200, height: 120)
    }
}
#endif
