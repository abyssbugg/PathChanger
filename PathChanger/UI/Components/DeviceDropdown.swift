//
//  DeviceDropdown.swift
//  PathChanger
//
//  Compact top-bar device selector — the SwiftUI port of the mockup's
//  `.device-sel` button + `.device-menu` popover (geospoofer-pro.html).
//
//  This is the first incremental slice of the UI redesign port. It reuses the
//  verified DesignSystem tokens (DS.Color / DS.Radius / DS.Metrics / DS.Typography)
//  so the control matches the HTML spec 1:1 without inventing new styling, and it
//  binds to the existing AppState device model (availableDevices / selectedDevice /
//  selectDevice / refreshDevices) so behavior is identical to DeviceTunnelPill's
//  selection surface.
//
//  Scope: device selection only. Tunnel/transport status stays owned by
//  DeviceTunnelPill; this component deliberately does not duplicate it.
//

import SwiftUI

struct DeviceDropdown: View {
    @EnvironmentObject var appState: AppState

    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(selectorLabel)
                    .font(DS.Typography.labelSecondary)
                    .foregroundStyle(DS.Color.foregroundPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.down")
                    .font(.system(size: DS.Metrics.deviceDropdownChevronSize, weight: .semibold))
                    .foregroundStyle(DS.Color.foregroundTertiary)
            }
            .padding(.horizontal, DS.Metrics.deviceDropdownHPadding)
            .frame(height: DS.Metrics.minButtonHeight)
        }
        .buttonStyle(DeviceSelectorButtonStyle(isHovered: isHovered))
        .onHover { hovering in
            withAnimation(DS.Animation.fast) { isHovered = hovering }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DeviceDropdownMenu(isPresented: $isPresented)
                .environmentObject(appState)
        }
        .accessibilityIdentifier("deviceDropdown")
        .accessibilityLabel(accessibilityLabel)
    }

    private var selectorLabel: String {
        guard let device = appState.selectedDevice else {
            return "Select device"
        }
        return "\(device.displayName) · iOS \(device.iosVersion)"
    }

    private var accessibilityLabel: String {
        "\(selectorLabel). Tap to switch devices."
    }
}

// MARK: - Selector button chrome (mockup `.device-sel`)

private struct DeviceSelectorButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(background(isPressed: isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(
                        DS.Color.foregroundTertiary.opacity(isHovered ? DS.Opacity.outline : DS.Opacity.divider),
                        lineWidth: DS.Metrics.strokeWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .animation(DS.Animation.fast, value: isHovered)
            .animation(DS.Animation.fast, value: isPressed)
    }

    private func background(isPressed: Bool) -> Color {
        if isPressed {
            return DS.Color.backgroundSecondary
        }
        if isHovered {
            return DS.Color.backgroundElevated
        }
        return DS.Color.backgroundSecondary.opacity(DS.Opacity.panel)
    }
}

// MARK: - Dropdown menu (mockup `.device-menu`)

private struct DeviceDropdownMenu: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            header

            if appState.availableDevices.isEmpty {
                emptyState
            } else {
                ForEach(appState.availableDevices) { device in
                    DeviceOptionRow(
                        device: device,
                        isSelected: appState.selectedDevice?.id == device.id
                    ) {
                        appState.selectDevice(device)
                        isPresented = false
                    }
                }
            }
        }
        .padding(DS.Metrics.deviceDropdownMenuPadding)
        .frame(minWidth: DS.Metrics.deviceDropdownMenuMinWidth, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Text("Devices")
                .font(DS.Typography.labelCaps)
                .foregroundStyle(DS.Color.foregroundTertiary)
                .textCase(.uppercase)
                .tracking(DS.Metrics.shortcutLabelTracking)

            Spacer()

            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await appState.refreshDevices()
                    isRefreshing = false
                }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(DS.Metrics.settingsProbeSpinnerScale)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.foregroundSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh device list")
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.xxs)
    }

    private var emptyState: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "iphone.slash")
                .foregroundStyle(DS.Color.inactive)
            Text("No iPhone connected")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.xs)
    }
}

// MARK: - Option row (mockup `.device-opt`)

private struct DeviceOptionRow: View {
    let device: Device
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(device.connectionType == .wifi ? DS.Color.mockupSky : DS.Color.mockupEmerald)
                    .frame(
                        width: DS.Metrics.deviceDropdownOptionDotSize,
                        height: DS.Metrics.deviceDropdownOptionDotSize
                    )

                Text(device.displayName)
                    .font(DS.Typography.labelSecondary)
                    .foregroundStyle(DS.Color.foregroundPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: DS.Spacing.xs)

                Text("iOS \(device.iosVersion)")
                    .font(DS.Typography.monoSmall)
                    .foregroundStyle(DS.Color.foregroundTertiary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Animation.fast) { isHovered = hovering }
        }
        .accessibilityLabel("Select \(device.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isSelected {
            return DS.Color.accent.opacity(DS.Opacity.selectionTint)
        }
        if isHovered {
            return DS.Color.backgroundElevated
        }
        return .clear
    }
}

#if DEBUG
struct DeviceDropdown_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Color.backgroundSecondary
            DeviceDropdown()
                .environmentObject(AppState())
        }
        .frame(width: DS.Metrics.devicePillWidth + DS.Spacing.xl, height: DS.Metrics.devicePillHeight + DS.Spacing.xxl)
    }
}
#endif
