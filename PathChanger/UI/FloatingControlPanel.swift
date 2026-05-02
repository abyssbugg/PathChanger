//
//  FloatingControlPanel.swift
//  PathChanger
//
//  Reusable glassmorphic container for floating UI controls
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
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let title = title {
                HStack(spacing: AppSpacing.sm) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundStyle(Color.pcPrimary)
                    }
                    Text(title)
                        .appSectionLabel()

                    Spacer()
                }
            }

            content
        }
        .padding(AppSpacing.lg)
        .appGlassPanel(cornerRadius: AppRadius.xl)
    }
}

#if DEBUG
struct FloatingControlPanel_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.blue.opacity(0.2).ignoresSafeArea()

            FloatingControlPanel(title: "Teleport", icon: "mappin.and.ellipse") {
                VStack {
                    TextField("Latitude", text: .constant("35.6812"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Longitude", text: .constant("139.7671"))
                        .textFieldStyle(.roundedBorder)
                    Button("Teleport") {}
                        .primaryButtonStyle()
                }
                .frame(width: 200)
            }
        }
    }
}
#endif
