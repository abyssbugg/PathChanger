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
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.sRGBLinear, red: 0.05, green: 0.05, blue: 0.1, opacity: 1.0),
                    Color(.sRGBLinear, red: 0.08, green: 0.06, blue: 0.12, opacity: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.red)

                    Text("Dependency Issue")
                        .font(AppFont.title)
                        .foregroundColor(.white)

                    Text("PathChanger requires additional setup before it can run")
                        .font(AppFont.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                Divider()
                    .background(Color.gray.opacity(0.3))

                // Errors List
                VStack(alignment: .leading, spacing: 16) {
                    Text("Issues Found")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)

                    ForEach(validator.errors) { error in
                        ErrorItemView(error: error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.sRGBLinear, red: 0.1, green: 0.08, blue: 0.15, opacity: 1.0))
                .cornerRadius(12)

                // Solution Section
                if let firstError = validator.errors.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to Fix")
                            .font(AppFont.caption)
                            .foregroundColor(.white)

                        Text(firstError.suggestion)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.sRGBLinear, red: 0.0, green: 0.15, blue: 0.0, opacity: 1.0))
                            .cornerRadius(8)

                        HStack(spacing: 12) {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(firstError.suggestion, forType: .string)
                                copiedToClipboard = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    copiedToClipboard = false
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copiedToClipboard ? "Copied!" : "Copy Command")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibleButton(
                                label: AccessibilityLabels.Actions.copyToClipboard,
                                hint: "Copies the suggested install or repair command",
                                identifier: "dependencyCopyCommandButton"
                            )

                            Link(destination: helpURL(for: firstError.type)) {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                    Text("Learn More")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.gray)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.sRGBLinear, red: 0.1, green: 0.12, blue: 0.1, opacity: 1.0))
                    .cornerRadius(12)
                }

                // Retry Section
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await validator.validateAll()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Validation")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibleButton(
                        label: "Retry dependency validation",
                        hint: "Checks Python and pymobiledevice3 again",
                        identifier: "dependencyRetryValidationButton"
                    )

                    Text("After installing the required dependencies, click above to retry.")
                        .font(AppFont.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
                .padding(32)
                .frame(maxWidth: 760)
            }
        }
        .frame(minWidth: 560, idealWidth: 800, minHeight: 480, idealHeight: 600)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: errorIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(errorColor)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(errorTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text(error.message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray)
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
            return .red
        case .pythonVersionTooOld, .pymobiledevice3VersionTooOld:
            return .yellow
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
