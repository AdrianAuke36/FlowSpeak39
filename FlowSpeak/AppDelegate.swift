import Cocoa
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Combine
import NaturalLanguage

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum MenuBarVisualState {
        case normal
        case warning
        case recording
    }

    private enum Constants {
        static let backendPollIntervalNanos: UInt64 = 15_000_000_000
        static let rewriteCopyDelayNanos: UInt64 = 170_000_000
        static let rewritePasteDelayNanos: UInt64 = 120_000_000
        static let fnDictationStartDelayNanos: UInt64 = 120_000_000
        static let fnReleaseGraceNanos: UInt64 = 220_000_000
    }

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private var statusItem: NSStatusItem!
    private let dictation = DictationController()
    private let overlay = OverlayController()
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    private var backendStatusItem: NSMenuItem?
    private var aiMenuItem: NSMenuItem?
    private var languageMenuItems: [AppLanguage: NSMenuItem] = [:]
    private var translationMenuItems: [AppLanguage: NSMenuItem] = [:]
    private var styleMenuItems: [WritingStyle: NSMenuItem] = [:]
    private var normalStatusImage: NSImage { makeMenuBarImage(state: .normal) }
    private var warningStatusImage: NSImage { makeMenuBarImage(state: .warning) }
    private var recordingStatusImage: NSImage { makeMenuBarImage(state: .recording) }
    private var backendOnline: Bool = false {
        didSet { updateStatusIcon(isRecording: false) }
    }
    private var fnIsDown: Bool = false
    private var shiftIsDown: Bool = false
    private var controlIsDown: Bool = false
    private var functionModifierIsDown: Bool = false
    private var didSetTranslationOverrideInCurrentFnHold: Bool = false
    private var pendingFnStartWorkItem: DispatchWorkItem?
    private var pendingFnReleaseWorkItem: DispatchWorkItem?
    private var didConsumeFnHoldForRewriteCombo: Bool = false
    private var isSelectionRewriteInProgress: Bool = false
    private var isCapturingRewriteInstruction: Bool = false
    private var pendingRewriteTargetApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureDictationCallbacks()

        // Be om Accessibility-tillatelse med dialog hvis ikke gitt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("🔐 AX ved oppstart: \(trusted)")

        setupStatusBar()
        setupFnKeyTap()
        refreshAIMenuTitle()
        applyLanguage(settings.appLanguage, persist: false)
        applyTranslationTarget(settings.translationTargetLanguage, persist: false)
        applyStyle(settings.writingStyle, persist: false)
        applyBackendConfiguration(
            baseURL: settings.backendBaseURL,
            token: settings.backendToken,
            persist: false
        )
        refreshLanguageMenuState()
        refreshTranslationMenuState()
        refreshStyleMenuState()
        observeSettingsChanges()

        Task { [weak self] in
            guard let self else { return }
            _ = await self.settings.refreshSupabaseSessionIfNeeded(force: false)
            await MainActor.run {
                self.applyBackendConfiguration(
                    baseURL: self.settings.backendBaseURL,
                    token: self.settings.backendToken,
                    persist: false
                )
            }
        }

        Task { await self.pollBackendHealth() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelPendingFnStart()
        cancelPendingFnReleaseAction()
    }

    private func observeSettingsChanges() {
        settings.$appLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyLanguage(language, persist: false)
            }
            .store(in: &cancellables)

        settings.$writingStyle
            .removeDuplicates()
            .sink { [weak self] style in
                self?.applyStyle(style, persist: false)
            }
            .store(in: &cancellables)

        settings.$translationTargetLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyTranslationTarget(language, persist: false)
            }
            .store(in: &cancellables)

        settings.$backendBaseURL
            .combineLatest(settings.$backendToken)
            .sink { [weak self] baseURL, token in
                self?.applyBackendConfiguration(baseURL: baseURL, token: token, persist: false)
            }
            .store(in: &cancellables)
    }

    private func configureDictationCallbacks() {
        dictation.onPartial = { [weak self] text in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isSelectionRewriteInProgress else { return }
                self.overlay.updatePartial(text)
            }
        }

        dictation.onFinal = { [weak self] text in
            guard let self else { return }
            guard !self.isSelectionRewriteInProgress else { return }
            self.runWhenCaptureIdle {
                self.overlay.showThinking(text)
            }
        }

        dictation.onInserted = { [weak self] in
            guard let self else { return }
            guard !self.isSelectionRewriteInProgress else { return }
            self.runWhenCaptureIdle {
                self.overlay.hide()
            }
        }
    }

    private func runWhenCaptureIdle(_ action: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Ignore stale callbacks from a previous dictation session.
            guard !self.dictation.isCaptureActive else { return }
            action()
        }
    }

    // MARK: - fn-tast via NSEvent local+global monitor

    private func setupFnKeyTap() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChangedEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChangedEvent(event)
            return event
        }
    }

    private func handleFlagsChangedEvent(_ event: NSEvent) {
        updateModifierState(from: event)
        let fnDown = functionModifierIsDown
        let shiftDown = shiftIsDown
        let controlDown = controlIsDown

        if fnDown {
            cancelPendingFnReleaseAction()
        }

        if fnDown && controlDown && !didConsumeFnHoldForRewriteCombo && !dictation.isCaptureActive && !isSelectionRewriteInProgress {
            fnIsDown = true
            didConsumeFnHoldForRewriteCombo = true
            cancelPendingFnStart()
            didSetTranslationOverrideInCurrentFnHold = false
            beginRewriteFromVoiceInstruction()
            return
        }

        if fnDown && shiftDown && !controlDown && !didSetTranslationOverrideInCurrentFnHold && !didConsumeFnHoldForRewriteCombo && !isSelectionRewriteInProgress {
            let targetLanguage = settings.translationTargetLanguage.targetLanguageCode
            dictation.setOneShotOutputLanguageOverride(targetLanguage)
            didSetTranslationOverrideInCurrentFnHold = true
            print("🌍 one-shot translation: \(targetLanguage) (\(settings.translationTargetLanguage.menuLabel), fn+Shift)")
        }

        if fnDown && !fnIsDown {
            fnIsDown = true
            didConsumeFnHoldForRewriteCombo = false
            scheduleFnStartIfNeeded()
        } else if !fnDown && fnIsDown {
            fnIsDown = false
            cancelPendingFnStart()
            didSetTranslationOverrideInCurrentFnHold = false
            if didConsumeFnHoldForRewriteCombo {
                didConsumeFnHoldForRewriteCombo = false
                scheduleFnReleaseAction { [weak self] in
                    self?.finishRewriteInstructionCaptureIfNeeded()
                }
                return
            }
            scheduleFnReleaseAction { [weak self] in
                self?.handleFnReleased()
            }
        }

        if fnDown && dictation.isCaptureActive {
            if isSelectionRewriteInProgress {
                overlay.setListeningMode(.rewrite)
            } else {
                overlay.setListeningMode(shiftDown ? .translation : .standard)
            }
        }
        if !fnDown {
            didSetTranslationOverrideInCurrentFnHold = false
        }
    }

    private func scheduleFnStartIfNeeded() {
        cancelPendingFnStart()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.fnIsDown else { return }
            guard !self.controlIsDown else { return }
            guard !self.didConsumeFnHoldForRewriteCombo else { return }
            self.handleFnPressed()
        }
        pendingFnStartWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .nanoseconds(Int(Constants.fnDictationStartDelayNanos)),
            execute: work
        )
    }

    private func cancelPendingFnStart() {
        pendingFnStartWorkItem?.cancel()
        pendingFnStartWorkItem = nil
    }

    private func scheduleFnReleaseAction(_ action: @escaping () -> Void) {
        cancelPendingFnReleaseAction()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.fnIsDown else { return }
            action()
        }
        pendingFnReleaseWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .nanoseconds(Int(Constants.fnReleaseGraceNanos)),
            execute: work
        )
    }

    private func cancelPendingFnReleaseAction() {
        pendingFnReleaseWorkItem?.cancel()
        pendingFnReleaseWorkItem = nil
    }

    private func updateModifierState(from event: NSEvent) {
        let flags = event.modifierFlags
        // Always derive full modifier state from event flags. Relying on changed key
        // alone makes fn detection flaky across keyboards and after repeated holds.
        functionModifierIsDown = flags.contains(.function)
        shiftIsDown = flags.contains(.shift)
        controlIsDown = flags.contains(.control)
    }

    private func handleFnPressed() {
        guard !dictation.isCaptureActive else { return }
        dictation.prefetchContext()
        overlay.showListening(mode: shiftIsDown ? .translation : .standard)
        dictation.start()
        updateStatusIcon(isRecording: true)
    }

    private func handleFnReleased() {
        guard dictation.isCaptureActive else { return }
        overlay.hide()
        dictation.stopAndInsert()
        updateStatusIcon(isRecording: false)

        // DEBUG – fjern etter testing
        print("🔐 AX trusted: \(AXIsProcessTrusted())")
    }

    // MARK: - Selection rewrite

    private func beginRewriteFromVoiceInstruction() {
        guard !isSelectionRewriteInProgress else { return }
        guard !dictation.isCaptureActive else { return }
        guard AXIsProcessTrusted() else {
            presentRewriteError("Accessibility permission is required to rewrite selected text.")
            return
        }

        pendingRewriteTargetApp = NSWorkspace.shared.frontmostApplication
        isSelectionRewriteInProgress = true
        isCapturingRewriteInstruction = true
        overlay.showListening(mode: .rewrite)
        dictation.start()
        updateStatusIcon(isRecording: true)
    }

    private func finishRewriteInstructionCaptureIfNeeded() {
        guard isCapturingRewriteInstruction else { return }
        isCapturingRewriteInstruction = false

        let instruction = dictation
            .stopAndCaptureInstruction()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        updateStatusIcon(isRecording: false)

        guard !instruction.isEmpty else {
            pendingRewriteTargetApp = nil
            isSelectionRewriteInProgress = false
            overlay.hide()
            return
        }

        let targetApp = pendingRewriteTargetApp
        pendingRewriteTargetApp = nil
        Task { [weak self] in
            await self?.performSelectionRewrite(
                instruction: instruction,
                targetApp: targetApp
            )
        }
    }

    @objc private func rewriteSelectedText() {
        if isCapturingRewriteInstruction {
            finishRewriteInstructionCaptureIfNeeded()
            return
        }

        guard !isSelectionRewriteInProgress else { return }
        didConsumeFnHoldForRewriteCombo = true
        beginRewriteFromVoiceInstruction()
    }

    @MainActor
    private func performSelectionRewrite(instruction: String, targetApp: NSRunningApplication?) async {
        defer {
            isSelectionRewriteInProgress = false
            overlay.hide()
        }

        guard let targetApp else {
            presentRewriteError("Could not find the target app with selected text.")
            return
        }

        targetApp.activate(options: [.activateIgnoringOtherApps])
        overlay.showListening(mode: .rewrite)
        try? await Task.sleep(nanoseconds: Constants.rewriteCopyDelayNanos)

        let snapshot = capturePasteboardSnapshot()
        sendCmdC()
        try? await Task.sleep(nanoseconds: Constants.rewriteCopyDelayNanos)

        let selectedText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selectedText.isEmpty else {
            restorePasteboardSnapshot(snapshot)
            presentRewriteError("No selected text found. Highlight text and try again.")
            return
        }

        let rewriteTargetLanguage = inferredRewriteTargetLanguage(from: selectedText)
        if let rewriteTargetLanguage {
            print("✏️ rewrite target lang:", rewriteTargetLanguage)
        }

        do {
            let result = try await AIClient.shared.rewrite(
                text: selectedText,
                instruction: instruction,
                targetLanguageOverride: rewriteTargetLanguage
            )
            let rewritten = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewritten.isEmpty else {
                restorePasteboardSnapshot(snapshot)
                presentRewriteError("AI returned empty text.")
                return
            }

            writeStringToPasteboard(rewritten)
            sendCmdV()
            try? await Task.sleep(nanoseconds: Constants.rewritePasteDelayNanos)
            restorePasteboardSnapshot(snapshot)
            print("✏️ rewrite done | chars:", selectedText.count, "->", rewritten.count)
        } catch {
            restorePasteboardSnapshot(snapshot)
            presentRewriteError("Rewrite failed: \(error.localizedDescription)")
        }
    }

    private func inferredRewriteTargetLanguage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return nil }

        switch dominant.rawValue {
        case "en":
            return "en-US"
        case "no", "nb", "nn":
            return "nb-NO"
        case "und":
            return nil
        default:
            return dominant.rawValue
        }
    }

    private func presentRewriteError(_ message: String) {
        print("❌ rewrite:", message)
        let alert = NSAlert()
        alert.messageText = "Rewrite Selected Text"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func capturePasteboardSnapshot() -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        let copiedItems = (pb.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        }
        return PasteboardSnapshot(items: copiedItems)
    }

    private func restorePasteboardSnapshot(_ snapshot: PasteboardSnapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let restoredItems = snapshot.items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(restoredItems)
    }

    private func writeStringToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func sendCmdC() {
        postKeyPress(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    private func sendCmdV() {
        postKeyPress(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    private func postKeyPress(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Backend health

    private func pollBackendHealth() async {
        while true {
            let online = await AIClient.shared.checkHealth()
            DispatchQueue.main.async {
                self.backendOnline = online
                self.updateBackendMenuItem(online: online)
            }
            try? await Task.sleep(nanoseconds: Constants.backendPollIntervalNanos)
        }
    }

    private func updateBackendMenuItem(online: Bool) {
        let translateLabel = settings.translationTargetLanguage.menuLabel
        backendStatusItem?.title = online
            ? "Backend: ✅ online  •  Hold fn (fn+Shift = Translate → \(translateLabel))"
            : "Backend: ⚠️ offline  •  Start server!"
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusButton()

        let menu = NSMenu()

        let backendItem = NSMenuItem(title: "Sjekker backend…", action: nil, keyEquivalent: "")
        backendStatusItem = backendItem
        menu.addItem(backendItem)

        menu.addItem(makeMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))

        let aiItem = makeMenuItem(title: "AI Polish: ON", action: #selector(toggleAI))
        menu.addItem(aiItem)
        aiMenuItem = aiItem
        menu.addItem(makeMenuItem(title: "Rewrite Selected Text…", action: #selector(rewriteSelectedText)))

        menu.addItem(makeLanguageRootMenuItem())
        menu.addItem(makeTranslationRootMenuItem())
        menu.addItem(makeStyleRootMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = normalStatusImage
        button.toolTip = "FlowSpeak"
    }

    private func makeMenuItem(title: String, action: Selector?, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func makeLanguageRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: "Language")
        languageMenuItems.removeAll()

        for language in AppLanguage.allCases {
            let item = makeMenuItem(title: language.menuLabel, action: #selector(selectLanguage(_:)))
            item.representedObject = language.rawValue
            languageMenu.addItem(item)
            languageMenuItems[language] = item
        }

        rootItem.submenu = languageMenu
        return rootItem
    }

    private func makeStyleRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu(title: "Style")
        styleMenuItems.removeAll()

        for style in WritingStyle.allCases {
            let item = makeMenuItem(title: style.menuLabel, action: #selector(selectStyle(_:)))
            item.representedObject = style.rawValue
            styleMenu.addItem(item)
            styleMenuItems[style] = item
        }

        rootItem.submenu = styleMenu
        return rootItem
    }

    private func makeTranslationRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Translate", action: nil, keyEquivalent: "")
        let translationMenu = NSMenu(title: "Translate")
        translationMenuItems.removeAll()

        for language in AppLanguage.allCases {
            let item = makeMenuItem(title: language.menuLabel, action: #selector(selectTranslationTarget(_:)))
            item.representedObject = language.rawValue
            translationMenu.addItem(item)
            translationMenuItems[language] = item
        }

        rootItem.submenu = translationMenu
        return rootItem
    }

    private func updateStatusIcon(isRecording: Bool) {
        statusItem.button?.image = image(for: menuBarState(isRecording: isRecording))
        statusItem.button?.title = ""
    }

    private func menuBarState(isRecording: Bool) -> MenuBarVisualState {
        if isRecording { return .recording }
        if !backendOnline && dictation.aiEnabled { return .warning }
        return .normal
    }

    private func image(for state: MenuBarVisualState) -> NSImage {
        switch state {
        case .normal: return normalStatusImage
        case .warning: return warningStatusImage
        case .recording: return recordingStatusImage
        }
    }

    private func makeMenuBarImage(state: MenuBarVisualState) -> NSImage {
        let size = NSSize(width: 19, height: 19)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let pillRect = NSRect(x: 1.6, y: 5.5, width: 15.8, height: 7.0)
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3.5, yRadius: 3.5)

        let ringColor: NSColor
        let fillColor: NSColor
        let barColor: NSColor
        switch state {
        case .normal:
            ringColor = NSColor.labelColor.withAlphaComponent(0.45)
            fillColor = NSColor.labelColor.withAlphaComponent(0.10)
            barColor = NSColor.labelColor
        case .warning:
            ringColor = NSColor.systemOrange.withAlphaComponent(0.85)
            fillColor = NSColor.systemOrange.withAlphaComponent(0.18)
            barColor = NSColor.systemOrange
        case .recording:
            ringColor = NSColor.systemRed.withAlphaComponent(0.90)
            fillColor = NSColor.systemRed.withAlphaComponent(0.18)
            barColor = NSColor.systemRed
        }

        fillColor.setFill()
        pill.fill()

        ringColor.setStroke()
        pill.lineWidth = 1.05
        pill.stroke()

        // Brighter top edge for a more "glass pill" look from the main logo.
        let topEdge = NSBezierPath()
        topEdge.move(to: NSPoint(x: pillRect.minX + 0.9, y: pillRect.maxY - 1.2))
        topEdge.line(to: NSPoint(x: pillRect.maxX - 0.9, y: pillRect.maxY - 1.2))
        NSColor.white.withAlphaComponent(0.18).setStroke()
        topEdge.lineWidth = 0.8
        topEdge.stroke()

        // Asymmetric waveform, closer to the SVG logo profile.
        let heights: [CGFloat] = [2.2, 3.9, 5.6, 4.7, 6.6, 4.4, 2.8]
        let barWidth: CGFloat = 1.05
        let gap: CGFloat = 0.92
        var x: CGFloat = 4.25
        let centerY: CGFloat = 9.0

        barColor.setFill()
        for h in heights {
            let y = centerY - (h / 2.0)
            let bar = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: h), xRadius: 0.52, yRadius: 0.52)
            bar.fill()
            x += barWidth + gap
        }

        if state == .recording {
            let dot = NSBezierPath(ovalIn: NSRect(x: 14.2, y: 13.0, width: 2.6, height: 2.6))
            NSColor.systemRed.setFill()
            dot.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            dot.lineWidth = 0.6
            dot.stroke()
        }

        image.isTemplate = false
        return image
    }

    private func refreshAIMenuTitle() {
        aiMenuItem?.title = dictation.aiEnabled ? "AI Polish: ON" : "AI Polish: OFF"
    }

    private func refreshLanguageMenuState() {
        for (language, item) in languageMenuItems {
            item.state = settings.appLanguage == language ? .on : .off
        }
    }

    private func refreshTranslationMenuState() {
        for (language, item) in translationMenuItems {
            item.state = settings.translationTargetLanguage == language ? .on : .off
        }
    }

    private func refreshStyleMenuState() {
        for (style, item) in styleMenuItems {
            item.state = settings.writingStyle == style ? .on : .off
        }
    }

    private func applyLanguage(_ language: AppLanguage, persist: Bool) {
        if persist {
            settings.appLanguage = language
        }
        dictation.setLanguage(language)
        refreshLanguageMenuState()
    }

    private func applyTranslationTarget(_ language: AppLanguage, persist: Bool) {
        if persist {
            settings.translationTargetLanguage = language
        }
        refreshTranslationMenuState()
        updateBackendMenuItem(online: backendOnline)
    }

    private func applyStyle(_ style: WritingStyle, persist: Bool) {
        if persist {
            settings.writingStyle = style
        }
        dictation.setStyle(style)
        refreshStyleMenuState()
    }

    private func applyBackendConfiguration(baseURL: String, token: String, persist: Bool) {
        if persist {
            settings.backendBaseURL = baseURL
            settings.backendToken = token
        }

        let normalizedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AIClient.shared.baseURLString = normalizedURL.isEmpty ? AppSettings.defaultBackendBaseURL : normalizedURL
        AIClient.shared.backendToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func toggleAI() {
        dictation.aiEnabled.toggle()
        refreshAIMenuTitle()
        updateStatusIcon(isRecording: false)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw)
        else { return }
        applyLanguage(language, persist: true)
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = WritingStyle(rawValue: raw)
        else { return }
        applyStyle(style, persist: true)
    }

    @objc private func selectTranslationTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw)
        else { return }
        applyTranslationTarget(language, persist: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
