//
//  OrganicSlider.swift
//  PathChanger
//
//  Auto + range control from the pth mock.
//

import SwiftUI

struct OrganicSliderRow: View {
    let title: String
    let valueLabel: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var isAuto: Bool = false
    /// Nil hides the Auto toggle; the slider is then always manual.
    var onToggleAuto: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Organic.body(12, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .frame(width: 72, alignment: .leading)

            if let onToggleAuto {
                Button(action: onToggleAuto) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isAuto ? Organic.sage800 : Organic.neutral600)
                        .frame(width: 26, height: 22)
                        .background(isAuto ? Organic.sage100 : Color.clear)
                        .overlay(
                            Capsule().stroke(isAuto ? Organic.sage600 : Organic.neutral400, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(isAuto ? "Auto — follow travel mode" : "Manual")
                .accessibilityLabel("Automatic speed")
                .accessibilityValue(isAuto ? "On, follows the travel mode" : "Off")
            }

            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueLabel)
                .disabled(sliderIsAuto)
                .opacity(sliderIsAuto ? 0.55 : 1)
                .tint(Organic.accent600)
                .controlSize(.small)

            Text(valueLabel)
                .font(Organic.mono(11.5))
                .foregroundStyle(Organic.neutral700)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private var sliderIsAuto: Bool { isAuto && onToggleAuto != nil }
}
