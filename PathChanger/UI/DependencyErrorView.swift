//
//  DependencyErrorView.swift
//  PathChanger
//
//  UI view for displaying and guiding resolution of dependency errors
//

import SwiftUI

struct DependencyErrorView: View {
    @ObservedObject var validator: DependencyValidator
    @State private var copiedToClipboard = false

    var body: some View {
        ZStack {
            Color.pcBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.md) {
                // Header
                VStack(spacing: DS.Metrics.dependencyActionHPadding) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.Typography.iconLarge)
                        .foregroundColor(.pcDanger)

                    Text("Dependency Issue")
                        .font(AppFont.title)
                        .foregroundColor(.pcText)

                    Text("PathChanger requires additional setup before it can run")
                        .font(AppFont.body)
                        .foregroundColor(.pcTextMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DS.Metrics.dependencyTopPadding)

                Divider()
                    .background(Color.pcOutline.opacity(AppSurfaceAlpha.divider))

                // Errors List
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Issues Found")
                        .font(AppFont.heading)
                        .foregroundColor(.pcText)
                        .padding(.bottom, AppSpacing.xs)

                    ForEach(validator.errors) { error in
                        ErrorItemView(error: error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Metrics.dependencyCardPadding)
                .background(Color.pcSurface.opacity(AppSurfaceAlpha.panel))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))

                // Solution Section
                if let firstError = validator.errors.first {
                    VStack(alignment: .leading, spacing: DS.Metrics.dependencyActionHPadding) {
                        Text("How to Fix")
                            .font(AppFont.caption)
                            .foregroundColor(.pcText)

                        Text(firstError.suggestion)
                            .font(AppFont.monospace)
                            .foregroundColor(.pcSecondary)
                            .padding(DS.Metrics.dependencyActionHPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        HStack(spacing: DS.Metrics.dependencyActionHPadding) {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(firstError.suggestion, forType: .string)
                                copiedToClipboard = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(DS.Metrics.two)) {
                                    copiedToClipboard = false
                                }
                            }) {
                                HStack(spacing: AppSpacing.xs) {
                                    Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copiedToClipboard ? "Copied!" : "Copy Command")
                                }
                                .font(AppFont.label)
                                .foregroundColor(.pcText)
                                .padding(.vertical, DS.Metrics.dependencyActionVPadding)
                                .padding(.horizontal, DS.Metrics.dependencyActionHPadding)
                                .background(Color.pcAccent)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibleButton(
                                label: AccessibilityLabels.Actions.copyToClipboard,
                                hint: "Copies the suggested install or repair command",
                                identifier: "dependencyCopyCommandButton"
                            )

                            Link(destination: helpURL(for: firstError.type)) {
                                HStack(spacing: AppSpacing.xs) {
                                    Image(systemName: "link")
                                    Text("Learn More")
                                }
                                .font(AppFont.label)
                                .foregroundColor(.pcText)
                                .padding(.vertical, DS.Metrics.dependencyActionVPadding)
                                .padding(.horizontal, DS.Metrics.dependencyActionHPadding)
                                .background(Color.pcSurfaceHighest)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Metrics.dependencyCardPadding)
                    .background(Color.pcSurface.opacity(AppSurfaceAlpha.panel))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                }

                // Retry Section
                VStack(spacing: DS.Metrics.dependencyActionHPadding) {
                    Button(action: {
                        Task {
                            await validator.validateAll()
                        }
                    }) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Validation")
                        }
                        .font(AppFont.label)
                        .foregroundColor(.pcText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Metrics.dependencyRetryButtonVPadding)
                        .background(Color.pcAccent)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibleButton(
                        label: "Retry dependency validation",
                        hint: "Checks Python and pymobiledevice3 again",
                        identifier: "dependencyRetryValidationButton"
                    )

                    Text("After installing the required dependencies, click above to retry.")
                        .font(AppFont.caption)
                        .foregroundColor(.pcTextMuted)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
                .padding(AppSpacing.lg)
                .frame(maxWidth: DS.Metrics.dependencyMaxWidth)
            }
        }
        .frame(
            minWidth: DS.Metrics.dependencyMinWidth,
            idealWidth: DS.Metrics.dependencyIdealWidth,
            minHeight: DS.Metrics.dependencyMinHeight,
            idealHeight: DS.Metrics.dependencyIdealHeight
        )
    }

    private func helpURL(for type: DependencyValidator.ValidationError.ErrorType) -> URL {
        switch type {
        case .pythonMissing, .pythonVersionTooOld, .pythonNotExecutable:
            return URL(string: "https://www.python.org/downloads/macos/")!
        case .pymobiledevice3Missing, .pymobiledevice3VersionTooOld:
            return URL(string: "https://github.com/doronz88/pymobiledevice3")!
        }
    }
}

// MARK: - Error Item View

struct ErrorItemView: View {
    let error: DependencyValidator.ValidationError

    var body: some View {
        HStack(alignment: .top, spacing: DS.Metrics.dependencyActionHPadding) {
            Image(systemName: errorIcon)
                .font(AppFont.heading)
                .foregroundColor(errorColor)
                .padding(.top, DS.Metrics.mapMarkerStrokeWidth)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(errorTitle)
                    .font(AppFont.label)
                    .foregroundColor(.pcText)

                Text(error.message)
                    .font(AppFont.metadata)
                    .foregroundColor(.pcTextMuted)
            }

            Spacer()
        }
    }

    var errorIcon: String {
        switch error.type {
        case .pythonMissing:
            return "xmark.circle.fill"
        case .pythonVersionTooOld:
            return "exclamationmark.circle.fill"
        case .pymobiledevice3Missing:
            return "xmark.circle.fill"
        case .pymobiledevice3VersionTooOld:
            return "exclamationmark.circle.fill"
        case .pythonNotExecutable:
            return "lock.circle.fill"
        }
    }

    var errorColor: Color {
        switch error.type {
        case .pythonMissing, .pymobiledevice3Missing, .pythonNotExecutable:
            return .pcDanger
        case .pythonVersionTooOld, .pymobiledevice3VersionTooOld:
            return .pcWarning
        }
    }

    var errorTitle: String {
        switch error.type {
        case .pythonMissing:
            return "Python Not Found"
        case .pythonVersionTooOld:
            return "Python Version Too Old"
        case .pymobiledevice3Missing:
            return "pymobiledevice3 Not Installed"
        case .pymobiledevice3VersionTooOld:
            return "pymobiledevice3 Version Too Old"
        case .pythonNotExecutable:
            return "Python Not Executable"
        }
    }
}

#if DEBUG
struct DependencyErrorView_Previews: PreviewProvider {
    static var previews: some View {
        DependencyErrorView(validator: DependencyValidator.shared)
    }
}
#endif
