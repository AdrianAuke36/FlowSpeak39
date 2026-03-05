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
        static let panelSize = NSSize(width: 132, height: 56)
        static let panelBottomOffset: CGFloat = 32
        static let hideDelay: TimeInterval = 0.25
        static let saveToastSize = NSSize(width: 72, height: 72)
        static let saveToastBottomOffset: CGFloat = 34
        static let saveToastDuration: TimeInterval = 2.3
    }

    private var panel: NSPanel?
    private var saveToastPanel: NSPanel?
    private let state = OverlayState()
    private var pendingHideWorkItem: DispatchWorkItem?
    private var pendingSaveToastHideWorkItem: DispatchWorkItem?
    var onAccessoryButtonTap: (() -> Void)?

    init() {
        DispatchQueue.main.async {
            self.setupPanel()
        }
    }

    func showListening(mode: OverlayMode = .standard) {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        state.mode = mode
        state.isLocked = false
        state.active = true
        bringToFront()
    }

    func setListeningMode(_ mode: OverlayMode) {
        state.mode = mode
    }

    func setLocked(_ locked: Bool) {
        state.isLocked = locked
    }

    func hide() {
        state.active = false
        state.isLocked = false
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

    func showSavedToast() {
        pendingSaveToastHideWorkItem?.cancel()
        pendingSaveToastHideWorkItem = nil

        if saveToastPanel == nil {
            setupSaveToastPanel()
        }
        positionSaveToastBottomCenter()
        saveToastPanel?.contentView = NSHostingView(rootView: SaveToastPanelView())
        saveToastPanel?.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            self?.saveToastPanel?.orderOut(nil)
        }
        pendingSaveToastHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.saveToastDuration, execute: work)
    }

    private func setupPanel() {
        let host = NSHostingView(
            rootView: OverlayView(
                state: state,
                onAccessoryButtonTap: { [weak self] in
                    self?.onAccessoryButtonTap?()
                }
            )
        )
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
        p.ignoresMouseEvents = false
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

    private func setupSaveToastPanel() {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Constants.saveToastSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.hasShadow = false

        saveToastPanel = p
        positionSaveToastBottomCenter()
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

    private func positionSaveToastBottomCenter() {
        guard let screen = NSScreen.main, let saveToastPanel else { return }
        let frame = screen.visibleFrame
        let w = Constants.saveToastSize.width
        let h = Constants.saveToastSize.height
        let x = frame.midX - w / 2
        let y = frame.minY + Constants.saveToastBottomOffset
        saveToastPanel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
}

// MARK: - State

final class OverlayState: ObservableObject {
    @Published var active: Bool = false
    @Published var mode: OverlayMode = .standard
    @Published var isLocked: Bool = false
}

// MARK: - View

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    let onAccessoryButtonTap: () -> Void

    var body: some View {
        PillView(
            active: state.active,
            mode: state.mode,
            isLocked: state.isLocked,
            onAccessoryButtonTap: onAccessoryButtonTap
        )
        .frame(width: 132, height: 56)
    }
}

struct PillView: View {
    let active: Bool
    let mode: OverlayMode
    let isLocked: Bool
    let onAccessoryButtonTap: () -> Void
    @State private var glowOpacity: Double = 0.35

    private var accentColor: Color {
        switch mode {
        case .standard:
            return Color(red: 0.00, green: 0.48, blue: 1.00)
        case .translation:
            return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .rewrite:
            return Color(red: 1.00, green: 0.23, blue: 0.19)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            WaveView(active: active)

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 0.5, height: 20)

            Button(action: onAccessoryButtonTap) {
                ZStack {
                    Circle()
                        .fill(isLocked ? accentColor.opacity(0.16) : Color.white.opacity(0.12))
                        .overlay(
                            Circle()
                                .strokeBorder(isLocked ? accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )

                    if isLocked {
                        Circle()
                            .fill(Color(red: 1.00, green: 0.23, blue: 0.19))
                            .frame(width: 11, height: 11)
                            .shadow(
                                color: Color(red: 1.00, green: 0.23, blue: 0.19).opacity(0.5),
                                radius: 5,
                                x: 0,
                                y: 0
                            )
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                accentColor.opacity(active ? glowOpacity : 0.08),
                                lineWidth: 1.15
                            )
                    )
                    .shadow(color: accentColor.opacity(active ? 0.16 : 0), radius: 10, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 5)
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
    private let bars = 5

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<bars, id: \.self) { i in
                WaveBar(active: active, index: i)
            }
        }
        .frame(height: 24)
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
            .onAppear {
                if active {
                    startAnimating()
                }
            }
            .onChange(of: active) { _, isActive in
                animationTask?.cancel()
                animationTask = nil

                if isActive {
                    startAnimating()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        height = 2.5
                    }
                }
            }
    }

    private func startAnimating() {
        height = 2.5
        let task = DispatchWorkItem {
            withAnimation(
                .easeInOut(duration: 0.58 + Double(index) * 0.05)
                .repeatForever(autoreverses: true)
            ) {
                height = CGFloat.random(in: 12...22)
            }
        }
        animationTask = task
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(index) * 0.08,
            execute: task
        )
    }
}
