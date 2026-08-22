//
//  JoystickControlView.swift
//  PathChanger
//
//  On-map joystick from the pth mock.
//

import SwiftUI
import AppKit

struct JoystickControlView: View {
    @EnvironmentObject var appState: AppState
    @State private var knobPosition: CGPoint = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var keyMonitor: Any?

    private let outerRadius: CGFloat = 66
    private let innerRadius: CGFloat = 23

    var body: some View {
        ZStack {
            Circle()
                .fill(Organic.neutral100.opacity(0.82))
                .overlay(Circle().stroke(Organic.neutral400, lineWidth: 1))
                .shadow(color: Organic.shadow.opacity(0.16), radius: 10, y: 3)

            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Organic.neutral400)
                .padding(18)

            Circle()
                .fill(Organic.accent600)
                .frame(width: innerRadius * 2, height: innerRadius * 2)
                .shadow(color: Organic.shadow.opacity(0.2), radius: 6, y: 2)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Organic.neutral100)
                )
                .offset(x: knobPosition.x + dragOffset.width, y: knobPosition.y + dragOffset.height)
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            let maxOffset = outerRadius - innerRadius
                            let rawX = value.translation.width
                            let rawY = value.translation.height
                            let distance = sqrt(rawX * rawX + rawY * rawY)
                            let clamped = min(distance, maxOffset)
                            let angle = atan2(rawY, rawX)
                            let knobX = clamped * cos(angle)
                            let knobY = clamped * sin(angle)
                            state = CGSize(width: knobX, height: knobY)
                            let normalizedX = knobX / maxOffset
                            let normalizedY = -knobY / maxOffset
                            appState.updateJoystickDirection(CGPoint(x: normalizedX, y: normalizedY))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                knobPosition = .zero
                            }
                            appState.updateJoystickDirection(.zero)
                        }
                )
        }
        .frame(width: 132, height: 132)
        .focusable()
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let mapping: [UInt16: CGPoint] = [
                126: CGPoint(x: 0, y: 1),
                125: CGPoint(x: 0, y: -1),
                123: CGPoint(x: -1, y: 0),
                124: CGPoint(x: 1, y: 0)
            ]
            guard let direction = mapping[event.keyCode] else { return event }
            if event.type == .keyDown {
                if !appState.isSimulating {
                    Task { await appState.startSimulation() }
                }
                appState.updateJoystickDirection(direction)
            } else {
                appState.updateJoystickDirection(.zero)
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

#if DEBUG
struct JoystickControlView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Organic.neutral200
            JoystickControlView()
                .environmentObject(AppState())
        }
        .frame(width: 200, height: 200)
    }
}
#endif
