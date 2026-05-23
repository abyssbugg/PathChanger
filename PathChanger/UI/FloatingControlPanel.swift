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
    let content: Content

    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        // Operational refinement: tighter rhythm (md/md) instead of (lg/lg)
        // so mode panels feel denser without redesigning the container.
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let title = title {
                HStack(spacing: AppSpacing.sm) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(AppFont.label)
                            .foregroundStyle(Color.pcTextMuted)
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
        .appGlassPanel(cornerRadius: AppRadius.xl)
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
                .frame(width: 200)
            }
        }
    }
}
#endif
