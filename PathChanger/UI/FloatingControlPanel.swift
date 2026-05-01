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
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                HStack {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()
                }
            }

            content
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
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
