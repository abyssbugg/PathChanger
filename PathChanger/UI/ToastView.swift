//
//  ToastView.swift
//  PathChanger
//
//  Toast notification system with queue management and auto-dismiss
//

import SwiftUI

// MARK: - Toast Type

enum ToastType {
    case success
    case error
    case warning
    case info
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

// MARK: - Toast Model

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
    let duration: TimeInterval
    
    init(type: ToastType, message: String, duration: TimeInterval = 3.0) {
        self.type = type
        self.message = message
        self.duration = duration
    }
    
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast Manager

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published private(set) var toasts: [Toast] = []
    
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private let maxVisibleToasts = 3
    
    private init() {}
    
    /// Show a toast notification
    func show(_ toast: Toast) {
        // Prevent duplicate messages
        guard !toasts.contains(where: { $0.message == toast.message }) else {
            return
        }
        
        withAnimation(.spring(response: 0.4)) {
            toasts.append(toast)
            
            // Remove oldest toast if exceeding limit
            if toasts.count > maxVisibleToasts {
                if let first = toasts.first {
                    dismiss(first)
                }
            }
        }
        
        // Auto-dismiss after duration
        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            dismiss(toast)
        }
        
        dismissTasks[toast.id] = task
    }
    
    /// Show success toast
    func success(_ message: String, duration: TimeInterval = 3.0) {
        show(Toast(type: .success, message: message, duration: duration))
    }
    
    /// Show error toast
    func error(_ message: String, duration: TimeInterval = 4.0) {
        show(Toast(type: .error, message: message, duration: duration))
    }
    
    /// Show warning toast
    func warning(_ message: String, duration: TimeInterval = 3.5) {
        show(Toast(type: .warning, message: message, duration: duration))
    }
    
    /// Show info toast
    func info(_ message: String, duration: TimeInterval = 3.0) {
        show(Toast(type: .info, message: message, duration: duration))
    }
    
    /// Dismiss a specific toast
    func dismiss(_ toast: Toast) {
        withAnimation(.easeOut(duration: 0.3)) {
            toasts.removeAll { $0.id == toast.id }
        }
        
        // Cancel auto-dismiss task
        dismissTasks[toast.id]?.cancel()
        dismissTasks.removeValue(forKey: toast.id)
    }
    
    /// Dismiss all toasts
    func dismissAll() {
        withAnimation(.easeOut(duration: 0.3)) {
            toasts.removeAll()
        }
        
        // Cancel all auto-dismiss tasks
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.title3)
                .foregroundColor(toast.type.color)
            
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 8)
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(toast.type.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Toast Container View

struct ToastContainerView: View {
    @ObservedObject var manager = ToastManager.shared
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(manager.toasts) { toast in
                ToastView(toast: toast) {
                    manager.dismiss(toast)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
        .frame(maxWidth: 500)
    }
}

// MARK: - View Extension

extension View {
    /// Add toast container overlay to a view
    func withToasts() -> some View {
        self.overlay(alignment: .top) {
            ToastContainerView()
        }
    }
}

// MARK: - Preview

struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 20) {
                Button("Show Success") {
                    ToastManager.shared.success("Location set successfully!")
                }
                
                Button("Show Error") {
                    ToastManager.shared.error("Failed to connect to device")
                }
                
                Button("Show Warning") {
                    ToastManager.shared.warning("Tunnel connection unstable")
                }
                
                Button("Show Info") {
                    ToastManager.shared.info("Checking for updates...")
                }
                
                Button("Show Multiple") {
                    ToastManager.shared.success("First toast")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        ToastManager.shared.error("Second toast")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        ToastManager.shared.info("Third toast")
                    }
                }
                
                Button("Dismiss All") {
                    ToastManager.shared.dismissAll()
                }
            }
            
            Spacer()
        }
        .frame(width: 600, height: 400)
        .withToasts()
    }
}
