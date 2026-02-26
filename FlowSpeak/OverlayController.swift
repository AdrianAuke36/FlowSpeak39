import AppKit
import SwiftUI
import Combine

enum OverlayMode {
    case standard
    case translation
    case rewrite
}

final class OverlayController {
    private enum Constants {
        static let panelSize = NSSize(width: 120, height: 52)
        static let panelBottomOffset: CGFloat = 32
        static let hideDelay: TimeInterval = 0.25
    }

    private var panel: NSPanel?
    private let state = OverlayState()
    private var pendingHideWorkItem: DispatchWorkItem?

    init() {
        DispatchQueue.main.async {
            self.setupPanel()
        }
    }

    func showListening(mode: OverlayMode = .standard) {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        state.mode = mode
        state.active = true
        bringToFront()
    }

    func setListeningMode(_ mode: OverlayMode) {
        state.mode = mode
    }

    func hide() {
        state.active = false
        pendingHideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.state.active else { return }
            self.panel?.orderOut(nil)
        }
        pendingHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.hideDelay, execute: work)
    }

    func updatePartial(_ text: String) { }
    func showThinking(_ text: String) { }

    private func setupPanel() {
        let host = NSHostingView(rootView: OverlayView(state: state))
        host.translatesAutoresizingMaskIntoConstraints = false

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Constants.panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.hasShadow = false

        p.contentView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: p.contentView!.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: p.contentView!.trailingAnchor),
            host.topAnchor.constraint(equalTo: p.contentView!.topAnchor),
            host.bottomAnchor.constraint(equalTo: p.contentView!.bottomAnchor),
        ])

        panel = p
        positionBottomCenter()
    }

    private func bringToFront() {
        panel?.orderFrontRegardless()
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main, let panel else { return }
        let frame = screen.visibleFrame
        let w = Constants.panelSize.width
        let h = Constants.panelSize.height
        let x = frame.midX - w / 2
        let y = frame.minY + Constants.panelBottomOffset
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
}

// MARK: - State

final class OverlayState: ObservableObject {
    @Published var active: Bool = false
    @Published var mode: OverlayMode = .standard
}

// MARK: - View

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        PillView(active: state.active, mode: state.mode)
            .frame(width: 120, height: 52)
    }
}

struct PillView: View {
    let active: Bool
    let mode: OverlayMode
    @State private var glowOpacity: Double = 0.35

    private var accentColor: Color {
        switch mode {
        case .standard:
            return Color(red: 0.38, green: 0.65, blue: 0.98) // blue
        case .translation:
            return Color(red: 0.33, green: 0.82, blue: 0.46) // green
        case .rewrite:
            return Color(red: 0.96, green: 0.30, blue: 0.30) // red
        }
    }

    var body: some View {
        WaveView(active: active)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                accentColor.opacity(active ? glowOpacity : 0.06),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: accentColor.opacity(active ? 0.18 : 0), radius: 10, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.55
                }
            }
    }
}

// MARK: - Wave

struct WaveView: View {
    let active: Bool
    private let bars = 7

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                WaveBar(active: active, index: i)
            }
        }
        .frame(height: 28)
    }
}

struct WaveBar: View {
    let active: Bool
    let index: Int

    @State private var height: CGFloat = 2.5
    @State private var animationTask: DispatchWorkItem?

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.88))
            .frame(width: 2.5, height: height)
            .onChange(of: active) { _, isActive in
                animationTask?.cancel()
                animationTask = nil

                if isActive {
                    height = 2.5
                    let task = DispatchWorkItem {
                        withAnimation(
                            .easeInOut(duration: 0.55 + Double(index) * 0.04)
                            .repeatForever(autoreverses: true)
                        ) {
                            height = CGFloat.random(in: 10...26)
                        }
                    }
                    animationTask = task
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + Double(index) * 0.07,
                        execute: task
                    )
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        height = 2.5
                    }
                }
            }
    }
}
