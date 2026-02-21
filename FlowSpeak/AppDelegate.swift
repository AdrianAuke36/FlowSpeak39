import Cocoa
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dictation = DictationController()
    private let overlay = OverlayController()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private var aiMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        dictation.onPartial = { [weak self] text in
            DispatchQueue.main.async {
                self?.overlay.updatePartial(text)
            }   
        }

        dictation.onFinal = { [weak self] text in
            DispatchQueue.main.async {
                self?.overlay.showThinking(text)
            }
        }

        // FIX: skjul overlay presist når insert er ferdig – ingen gjettet delay
        dictation.onInserted = { [weak self] in
            DispatchQueue.main.async {
                self?.overlay.hide()
            }
        }

        setupStatusBar()
        setupHotKeyPressedAndReleased()
        refreshAIMenuTitle()
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.title = "🎙️"
            button.toolTip = "FlowLite"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold ⌃⌥Space to talk", action: nil, keyEquivalent: ""))

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aiItem = NSMenuItem(title: "AI Polish: ON", action: #selector(toggleAI), keyEquivalent: "")
        aiItem.target = self
        menu.addItem(aiItem)
        self.aiMenuItem = aiItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatusIcon(isRecording: false)
    }

    private func updateStatusIcon(isRecording: Bool) {
        statusItem.button?.title = isRecording ? "🔴" : "🎙️"
    }

    private func refreshAIMenuTitle() {
        aiMenuItem?.title = dictation.aiEnabled ? "AI Polish: ON" : "AI Polish: OFF"
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func toggleAI() {
        dictation.aiEnabled.toggle()
        refreshAIMenuTitle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hotkey (hold-to-talk)

    private func setupHotKeyPressedAndReleased() {
        var eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()

            let kind = GetEventKind(eventRef)
            if kind == UInt32(kEventHotKeyPressed) {
                delegate.handleHotKeyPressed()
            } else if kind == UInt32(kEventHotKeyReleased) {
                delegate.handleHotKeyReleased()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            eventTypes.count,
            &eventTypes,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        var hotKeyID = EventHotKeyID(signature: OSType(0x464C4C54), id: 1)
        let modifiers: UInt32 = UInt32(controlKey) | UInt32(optionKey)

        RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func handleHotKeyPressed() {
        guard !dictation.isRecording else { return }

        overlay.showListening()
        dictation.start()
        updateStatusIcon(isRecording: true)
    }

    private func handleHotKeyReleased() {
        guard dictation.isRecording else { return }

        dictation.stopAndInsert()
        updateStatusIcon(isRecording: false)

        // FIX: overlay skjules via onInserted-callback i stedet for timer
        // Failsafe: uansett hva som skjer, skjul etter 8 sek
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            self?.overlay.hide()
        }
    }
}
