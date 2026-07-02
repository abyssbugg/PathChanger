//
//  TelemetryBar.swift
//  PathChanger
//
//  Bottom telemetry strip — the SwiftUI port of the mockup's footer
//  `.telemetry-bar` (geospoofer-pro.html), reduced to the signals the app
//  actually tracks: GPS/spoofing status, current coordinates, and the
//  configured simulation speed. No fabricated values (the mockup's demo
//  accuracy/altitude cells are omitted until real data exists).
//
//  Display-only by design: the mockup's footer Stop button is intentionally
//  NOT ported here — PrimaryActionPill is the SOLE production T0 execution
//  authority and already owns stop semantics.
//

import SwiftUI

struct TelemetryBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            cell(
                label: "GPS Status",
                value: statusText,
                icon: "dot.radiowaves.left.and.right",
                tint: appState.isSimulating ? DS.Color.mockupEmerald : DS.Color.inactive
            )

            divider

            cell(
                label: "Coordinates",
                value: TelemetryBar.coordinateText(appState.currentLocation),
                icon: "scope",
                tint: DS.Color.foregroundSecondary,
                monospaced: true
            )

            divider

            cell(
                label: "Speed",
                value: appState.simulationSpeed.displayName,
                icon: "speedometer",
                tint: DS.Color.foregroundSecondary
            )
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.backgroundSecondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("telemetryBar")
    }

    private var statusText: String {
        if appState.isSimulating {
            return appState.statusMessage ?? "Spoofing Active"
        }
        return "Standby"
    }

    /// Pure formatter (unit-testable): "37.774900, -122.418900" or an em dash.
    static func coordinateText(_ coordinate: LocationCoordinate?) -> String {
        guard let coordinate else { return "—" }
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Color.foregroundTertiary.opacity(DS.Opacity.divider))
            .frame(width: DS.Metrics.strokeWidth, height: DS.Metrics.mapToolbarDividerHeight)
    }

    private func cell(label: String, value: String, icon: String, tint: Color, monospaced: Bool = false) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.caption)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(DS.Typography.labelCaps)
                    .foregroundStyle(DS.Color.foregroundTertiary)
                    .tracking(DS.Metrics.shortcutLabelTracking)
                Text(value)
                    .font(monospaced ? DS.Typography.monoSmall : DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.foregroundPrimary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

#if DEBUG
struct TelemetryBar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Color.backgroundSecondary
            TelemetryBar()
                .environmentObject(AppState())
        }
        .frame(width: DS.Metrics.popoverWidth + DS.Spacing.xxl, height: DS.Metrics.devicePillHeight + DS.Spacing.xl)
    }
}
#endif
