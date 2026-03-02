import AppKit
import ApplicationServices
import AVFoundation
import Speech
import SwiftUI

enum PermissionType {
    case speechRecognition
    case microphone
    case accessibility
    case inputMonitoring

    var title: String { details.title }
    var message: String { details.message }
    var settingsURL: URL { details.settingsURL }

    private var details: Details {
        switch self {
        case .speechRecognition:
            return Details(
                title: "Speech Recognition Permission Required",
                message: "FlowSpeak needs speech recognition access to turn your voice into text. Enable it in System Settings, then try again.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
            )
        case .microphone:
            return Details(
                title: "Microphone Permission Required",
                message: "FlowSpeak needs microphone access to record when you hold fn. Enable it in System Settings, then try again.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            )
        case .accessibility:
            return Details(
                title: "Accessibility Permission Required",
                message: "FlowSpeak needs accessibility access to insert text into apps. Click below to enable it in System Settings.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        case .inputMonitoring:
            return Details(
                title: "Input Monitoring Required",
                message: "FlowSpeak needs input monitoring to detect the fn key. Click below to enable it in System Settings.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
            )
        }
    }

    private struct Details {
        let title: String
        let message: String
        let settingsURL: URL
    }
}

final class PermissionController {
    static let shared = PermissionController()

    private enum Constants {
        static let windowSize = NSSize(width: 420, height: 220)
        static let recheckDelay: TimeInterval = 3.0
    }

    private var window: NSWindow?

    @discardableResult
    func checkAndPromptIfNeededForFnPress() -> Bool {
        guard let missingPermission = firstBlockingPermissionForFnPress() else { return false }
        DispatchQueue.main.async { [weak self] in
            self?.show(type: missingPermission)
        }
        return true
    }

    @discardableResult
    func checkAndPromptIfNeededForRewrite() -> Bool {
        guard !AXIsProcessTrusted() else { return false }
        DispatchQueue.main.async { [weak self] in
            self?.show(type: .accessibility)
        }
        return true
    }

    func show(type: PermissionType) {
        guard window == nil else { return }

        let view = PermissionView(
            type: type,
            onOpenSettings: { [weak self] in self?.openSettings(for: type) },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Constants.windowSize)

        let permissionWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        permissionWindow.isOpaque = false
        permissionWindow.backgroundColor = .clear
        permissionWindow.level = .floating
        permissionWindow.contentView = host
        permissionWindow.center()
        permissionWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = permissionWindow
    }

    private func firstBlockingPermissionForFnPress() -> PermissionType? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            return .speechRecognition
        default:
            break
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            return .microphone
        default:
            break
        }

        if !AXIsProcessTrusted() { return .accessibility }
        if !CGPreflightListenEventAccess() { return .inputMonitoring }
        return nil
    }

    private func openSettings(for type: PermissionType) {
        NSWorkspace.shared.open(type.settingsURL)
        dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.recheckDelay) { [weak self] in
            switch type {
            case .accessibility:
                if !AXIsProcessTrusted() {
                    self?.show(type: .accessibility)
                }
            case .inputMonitoring:
                if !CGPreflightListenEventAccess() {
                    self?.show(type: .inputMonitoring)
                }
            case .speechRecognition:
                let status = SFSpeechRecognizer.authorizationStatus()
                if status == .denied || status == .restricted {
                    self?.show(type: .speechRecognition)
                }
            case .microphone:
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                if status == .denied || status == .restricted {
                    self?.show(type: .microphone)
                }
            }
        }
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}

struct PermissionView: View {
    private enum Layout {
        static let cornerRadius: CGFloat = 20
        static let closeButtonSize: CGFloat = 24
        static let iconCircleSize: CGFloat = 44
        static let iconSize: CGFloat = 22
        static let buttonHeight: CGFloat = 42
        static let horizontalPadding: CGFloat = 24
        static let width: CGFloat = 420
        static let height: CGFloat = 220
    }

    let type: PermissionType
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .frame(width: Layout.closeButtonSize, height: Layout.closeButtonSize)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
                .padding(.trailing, 16)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: Layout.iconCircleSize, height: Layout.iconCircleSize)
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: Layout.iconSize, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.9))
                    }

                    Text(type.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .multilineTextAlignment(.center)

                    Text(type.message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Layout.horizontalPadding)
                }

                Spacer(minLength: 16)

                Button(action: onOpenSettings) {
                    Text("Open Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.buttonHeight)
                        .background(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.bottom, 20)
            }
        }
        .frame(width: Layout.width, height: Layout.height)
    }
}
