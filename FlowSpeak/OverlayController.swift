//
//  OverlayController.swift
//  FlowSpeak
//
//  Created by Adrian Auke on 20/02/2026.
//


import AppKit
import SwiftUI
import Combine

final class OverlayController {
    private var panel: NSPanel?
    private let state = OverlayState()

    func showListening() {
        ensurePanel()
        state.status = "Listening…"
        state.text = ""
        bringToFront()
    }

    func updatePartial(_ text: String) {
        ensurePanel()
        state.status = "Listening…"
        state.text = text
        bringToFront()
    }

    func showThinking(_ finalText: String) {
        ensurePanel()
        state.status = "Thinking…"
        state.text = finalText
        bringToFront()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil { return }

        let host = NSHostingView(rootView: OverlayView(state: state))
        host.translatesAutoresizingMaskIntoConstraints = false

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
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

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true

        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        p.contentView = container
        panel = p

        positionBottomCenter()
    }

    private func bringToFront() {
        panel?.orderFrontRegardless()
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main, let panel else { return }
        let frame = screen.visibleFrame
        let w: CGFloat = 520
        let h: CGFloat = 120
        let x = frame.midX - w/2
        let y = frame.minY + 28
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
}

final class OverlayState: ObservableObject {
    @Published var status: String = "Listening…"
    @Published var text: String = ""
}

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)

            VStack(alignment: .leading, spacing: 8) {
                Text(state.status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(state.text.isEmpty ? "…" : state.text)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(width: 520, height: 120)
    }
}
