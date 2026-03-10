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

    private func ui(_ norwegian: String, _ english: String) -> String {
        AppSettings.shared.ui(norwegian, english)
    }

    private var details: Details {
        switch self {
        case .speechRecognition:
            return Details(
                title: ui("Talegjenkjenning kreves", "Speech Recognition Permission Required"),
                message: ui(
                    "BlueSpeak trenger tilgang til talegjenkjenning for å gjøre stemmen din om til tekst. Aktiver dette i Systeminnstillinger, og prøv igjen.",
                    "BlueSpeak needs speech recognition access to turn your voice into text. Enable it in System Settings, then try again."
                ),
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
            )
        case .microphone:
            return Details(
                title: ui("Mikrofontilgang kreves", "Microphone Permission Required"),
                message: ui(
                    "BlueSpeak trenger mikrofontilgang for å ta opp når du holder hovedtasten. Aktiver dette i Systeminnstillinger, og prøv igjen.",
                    "BlueSpeak needs microphone access to record when you hold fn. Enable it in System Settings, then try again."
                ),
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            )
        case .accessibility:
            return Details(
                title: ui("Tilgjengelighet kreves", "Accessibility Permission Required"),
                message: ui(
                    "BlueSpeak trenger tilgjengelighetstilgang for å sette inn tekst i apper. Trykk under for å aktivere i Systeminnstillinger.",
                    "BlueSpeak needs accessibility access to insert text into apps. Click below to enable it in System Settings."
                ),
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        case .inputMonitoring:
            return Details(
                title: ui("Inndataovervåking kreves", "Input Monitoring Required"),
                message: ui(
                    "BlueSpeak trenger inndataovervåking for å oppdage hovedtasten. Trykk under for å aktivere i Systeminnstillinger.",
                    "BlueSpeak needs input monitoring to detect the fn key. Click below to enable it in System Settings."
                ),
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
        if AppSettings.shared.speechRecognitionRequiredForDictation {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .denied, .restricted:
                return .speechRecognition
            default:
                break
            }
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
                if AppSettings.shared.speechRecognitionRequiredForDictation {
                    let status = SFSpeechRecognizer.authorizationStatus()
                    if status == .denied || status == .restricted {
                        self?.show(type: .speechRecognition)
                    }
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
    @ObservedObject private var settings = AppSettings.shared

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

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .fill(AppTheme.sheetMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cornerRadius)
                        .fill(AppTheme.surface.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cornerRadius)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
                .shadow(color: AppTheme.shadow, radius: 16, x: 0, y: 8)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: Layout.closeButtonSize, height: Layout.closeButtonSize)
                            .background(AppTheme.surfaceMuted.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
                .padding(.trailing, 16)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.destructive.opacity(0.14))
                            .frame(width: Layout.iconCircleSize, height: Layout.iconCircleSize)
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: Layout.iconSize, weight: .semibold))
                            .foregroundStyle(AppTheme.destructive)
                    }

                    Text(type.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text(type.message)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Layout.horizontalPadding)
                }

                Spacer(minLength: 16)

                Button(action: onOpenSettings) {
                    Text(ui("Åpne innstillinger", "Open Settings"))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.large)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.bottom, 20)
            }
        }
        .frame(width: Layout.width, height: Layout.height)
    }
}
