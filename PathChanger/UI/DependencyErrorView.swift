//
//  DependencyErrorView.swift
//  PathChanger
//
//  UI view for displaying and guiding resolution of dependency errors
//

import SwiftUI

struct DependencyErrorView: View {
    @ObservedObject var validator: DependencyValidator

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

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.red)

                    Text("Dependency Issue")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    Text("PathChanger needs pymobiledevice3 on this Mac. You can install it here.")
                        .font(.system(size: 14, weight: .regular))
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

                if validator.canInstallPymobiledevice3 || validator.validationStatus == .installing {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Install in PathChanger")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        Text("This rebuilds PathChanger's managed Python runtime (pyenv-first bootstrap) with the latest pymobiledevice3. Compatible runtimes are accepted by capability probe.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.gray)

                        if !validator.installProgress.isEmpty {
                            Text(validator.installProgress)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button(action: {
                            Task {
                                await validator.installLatestPymobiledevice3()
                            }
                        }) {
                            HStack(spacing: 8) {
                                if validator.validationStatus == .installing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                    Text("Installing…")
                                } else {
                                    Image(systemName: "arrow.down.app")
                                    Text("Install pymobiledevice3")
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(validator.validationStatus == .installing ? Color.gray : Color.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(validator.validationStatus == .installing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.sRGBLinear, red: 0.1, green: 0.12, blue: 0.1, opacity: 1.0))
                    .cornerRadius(12)
                }

                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await validator.validateAll()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Check Again")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(validator.validationStatus == .installing)
                }

                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
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
        case .pymobiledevice3CapabilitiesMissing:
            return "exclamationmark.circle.fill"
        case .pythonNotExecutable:
            return "lock.circle.fill"
        }
    }

    var errorColor: Color {
        switch error.type {
        case .pythonMissing, .pymobiledevice3Missing, .pythonNotExecutable:
            return .red
        case .pythonVersionTooOld, .pymobiledevice3CapabilitiesMissing:
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
        case .pymobiledevice3CapabilitiesMissing:
            return "pymobiledevice3 Capabilities Missing"
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
