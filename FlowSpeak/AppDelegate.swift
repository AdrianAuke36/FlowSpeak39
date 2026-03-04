import Cocoa
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Combine
import NaturalLanguage

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?

    private var backendStatusItem: NSMenuItem?
    private var aiMenuItem: NSMenuItem?
    private var signOutMenuItem: NSMenuItem?
    private var microphoneMenuItems: [String: NSMenuItem] = [:]
    private var languageMenuItems: [AppLanguage: NSMenuItem] = [:]
    private var translationMenuItems: [AppLanguage: NSMenuItem] = [:]
    private var styleMenuItems: [WritingStyle: NSMenuItem] = [:]
    private var interpretationMenuItems: [InterpretationLevel: NSMenuItem] = [:]
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
    private var leftOptionModifierIsDown: Bool = false
    private var rightOptionModifierIsDown: Bool = false
    private var leftCommandModifierIsDown: Bool = false
    private var rightCommandModifierIsDown: Bool = false
    private var didSetTranslationOverrideInCurrentFnHold: Bool = false
    private var pendingFnStartWorkItem: DispatchWorkItem?
    private var pendingFnReleaseWorkItem: DispatchWorkItem?
    private var didConsumeFnHoldForRewriteCombo: Bool = false
    private var isPersistentCaptureLocked: Bool = false
    private var isSelectionRewriteInProgress: Bool = false
    private var isSavingQuickReplyContext: Bool = false
    private var isCapturingRewriteInstruction: Bool = false
    private var pendingRewriteTargetApp: NSRunningApplication?
    private var quickReplyContextText: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogStore.shared.record(.info, "App launched")
        NSApp.setActivationPolicy(.accessory)

        configureDictationCallbacks()

        // Be om Accessibility-tillatelse med dialog hvis ikke gitt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("🔐 AX ved oppstart: \(trusted)")

        setupStatusBar()
        overlay.onAccessoryButtonTap = { [weak self] in
            self?.handleOverlayAccessoryButtonTap()
        }
        setupFnKeyTap()
        refreshAIMenuTitle()
        applyLanguage(settings.appLanguage, persist: false)
        applyTranslationTarget(settings.translationTargetLanguage, persist: false)
        applyStyle(settings.writingStyle, persist: false)
        applyInterpretationLevel(settings.interpretationLevel, persist: false)
        applyBackendConfiguration(
            baseURL: settings.backendBaseURL,
            token: settings.backendToken,
            persist: false
        )
        refreshMicrophoneMenuState()
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

        DispatchQueue.main.async { [weak self] in
            self?.configureHomeWindowBehavior()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureHomeWindowBehavior()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openHome()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelPendingFnStart()
        cancelPendingFnReleaseAction()
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isHomeWindow(sender) else { return true }
        sender.orderOut(nil)
        return false
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

        settings.$interpretationLevel
            .removeDuplicates()
            .sink { [weak self] interpretationLevel in
                self?.applyInterpretationLevel(interpretationLevel, persist: false)
            }
            .store(in: &cancellables)

        settings.$selectedMicrophoneUID
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshMicrophoneMenuState()
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
                self?.refreshSignOutMenuState()
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

        dictation.onCaptureInterrupted = { [weak self] message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.resetCaptureInteractionState()
                self.overlay.hide()
                self.updateStatusIcon(isRecording: false)
                if let message, !message.isEmpty {
                    print("⚠️ capture interrupted:", message)
                }
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
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChangedEvent(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChangedEvent(event)
            return event
        }
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDownEvent(event)
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDownEvent(event) ? nil : event
        }
    }

    private func handleFlagsChangedEvent(_ event: NSEvent) {
        if settings.isShortcutCaptureActive {
            return
        }
        updateModifierState(from: event)
        processModifierStateSnapshot()
    }

    @discardableResult
    private func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        if settings.isShortcutCaptureActive {
            return false
        }
        if event.isARepeat {
            return false
        }
        if !selectedTriggerIsDown || shiftIsDown || controlIsDown {
            return false
        }

        let isQuickReplyContextShortcut =
            event.keyCode == UInt16(kVK_ISO_Section) ||
            (event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) == "<")
        guard isQuickReplyContextShortcut else {
            return false
        }

        cancelPendingFnStart()
        if dictation.isCaptureActive {
            dictation.cancelCapture()
            isPersistentCaptureLocked = false
            overlay.setLocked(false)
            overlay.hide()
            updateStatusIcon(isRecording: false)
        }
        Task { @MainActor [weak self] in
            await self?.captureQuickReplyContext()
        }
        return true
    }

    private func processModifierStateSnapshot() {
        let fnDown = selectedTriggerIsDown
        let shiftDown = shiftIsDown
        let controlDown = controlIsDown

        if fnDown {
            cancelPendingFnReleaseAction()
        }

        if fnDown && !fnIsDown && isPersistentCaptureLocked && dictation.isCaptureActive {
            stopPersistentCapture()
            return
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
            print("🌍 one-shot translation: \(targetLanguage) (\(settings.translationTargetLanguage.menuLabel), \(settings.shortcutTriggerKey.translateShortcut))")
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
                if isPersistentCaptureLocked {
                    return
                }
                scheduleFnReleaseAction { [weak self] in
                    self?.finishRewriteInstructionCaptureIfNeeded()
                }
                return
            }
            if isPersistentCaptureLocked {
                return
            }
            scheduleFnReleaseAction { [weak self] in
                self?.handleFnReleased()
            }
        }

        if fnDown && dictation.isCaptureActive && !isPersistentCaptureLocked {
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

    private func resetCaptureInteractionState() {
        fnIsDown = false
        shiftIsDown = false
        controlIsDown = false
        functionModifierIsDown = false
        leftOptionModifierIsDown = false
        rightOptionModifierIsDown = false
        leftCommandModifierIsDown = false
        rightCommandModifierIsDown = false
        didSetTranslationOverrideInCurrentFnHold = false
        didConsumeFnHoldForRewriteCombo = false
        isPersistentCaptureLocked = false
        isSelectionRewriteInProgress = false
        isCapturingRewriteInstruction = false
        pendingRewriteTargetApp = nil
        cancelPendingFnStart()
        cancelPendingFnReleaseAction()
        overlay.setLocked(false)
    }

    private func updateModifierState(from event: NSEvent) {
        let flags = event.modifierFlags
        shiftIsDown = flags.contains(.shift)
        controlIsDown = flags.contains(.control)

        // Built-in keyboards usually set .function correctly. Some external keyboards
        // still send the fn/globe key as a flagsChanged event (keyCode 63) but do not
        // include the .function flag. For those keyboards, treat repeated function-key
        // flagsChanged events as a press/release toggle.
        if event.type == .flagsChanged && event.keyCode == UInt16(kVK_Function) {
            if flags.contains(.function) {
                functionModifierIsDown = true
            } else {
                functionModifierIsDown.toggle()
            }
        } else if event.type == .flagsChanged && event.keyCode == UInt16(kVK_Option) {
            leftOptionModifierIsDown.toggle()
        } else if event.type == .flagsChanged && event.keyCode == UInt16(kVK_RightOption) {
            rightOptionModifierIsDown.toggle()
        } else if event.type == .flagsChanged && event.keyCode == UInt16(kVK_Command) {
            leftCommandModifierIsDown.toggle()
        } else if event.type == .flagsChanged && event.keyCode == UInt16(kVK_RightCommand) {
            rightCommandModifierIsDown.toggle()
        }

        if flags.contains(.function) {
            functionModifierIsDown = true
        } else if !fnIsDown && !dictation.isCaptureActive && !isPersistentCaptureLocked && !isSelectionRewriteInProgress {
            functionModifierIsDown = false
        }

        if !flags.contains(.option) {
            leftOptionModifierIsDown = false
            rightOptionModifierIsDown = false
        }

        if !flags.contains(.command) {
            leftCommandModifierIsDown = false
            rightCommandModifierIsDown = false
        }
    }

    private var selectedTriggerIsDown: Bool {
        switch settings.shortcutTriggerKey {
        case .function:
            return functionModifierIsDown
        case .leftOption:
            return leftOptionModifierIsDown
        case .rightOption:
            return rightOptionModifierIsDown
        case .leftCommand:
            return leftCommandModifierIsDown
        case .rightCommand:
            return rightCommandModifierIsDown
        }
    }

    private func handleFnPressed() {
        guard !dictation.isCaptureActive else { return }
        if PermissionController.shared.checkAndPromptIfNeededForFnPress() {
            isPersistentCaptureLocked = false
            overlay.setLocked(false)
            overlay.hide()
            updateStatusIcon(isRecording: false)
            return
        }
        isPersistentCaptureLocked = false
        overlay.setLocked(false)
        dictation.prefetchContext()
        overlay.showListening(mode: shiftIsDown ? .translation : .standard)
        dictation.start()
        updateStatusIcon(isRecording: true)
    }

    private func handleFnReleased() {
        guard dictation.isCaptureActive else { return }
        isPersistentCaptureLocked = false
        overlay.setLocked(false)
        overlay.hide()
        dictation.stopAndInsert()
        updateStatusIcon(isRecording: false)

        // DEBUG – fjern etter testing
        print("🔐 AX trusted: \(AXIsProcessTrusted())")
    }

    @MainActor
    private func captureQuickReplyContext() async {
        guard !isSavingQuickReplyContext else { return }
        guard !dictation.isCaptureActive else { return }
        guard !isSelectionRewriteInProgress else { return }
        guard !PermissionController.shared.checkAndPromptIfNeededForRewrite() else { return }

        isSavingQuickReplyContext = true
        defer { isSavingQuickReplyContext = false }

        let targetApp = NSWorkspace.shared.frontmostApplication
        targetApp?.activate(options: [])
        try? await Task.sleep(nanoseconds: Constants.rewriteCopyDelayNanos)

        let (snapshot, selectedText) = await readSelectedTextFromFocusedApp()
        defer { restorePasteboardSnapshot(snapshot) }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSSound.beep()
            AppLogStore.shared.record(.warning, "Quick reply context capture failed", metadata: ["reason": "No selected text"])
            return
        }

        quickReplyContextText = trimmed
        playQuickReplySavedSound()
        overlay.showSavedToast()
        AppLogStore.shared.record(.info, "Quick reply context saved", metadata: ["chars": "\(trimmed.count)"])
        print("💾 quick reply context saved | chars:", trimmed.count)
    }

    private func playQuickReplySavedSound() {
        if let sound = NSSound(named: "Glass") ?? NSSound(named: "Hero") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    @MainActor
    private func readSelectedTextFromFocusedApp() async -> (PasteboardSnapshot, String) {
        let snapshot = capturePasteboardSnapshot()
        let sentinel = "__flowspeak_selection__\(UUID().uuidString)"
        writeStringToPasteboard(sentinel)
        sendCmdC()
        try? await Task.sleep(nanoseconds: Constants.rewriteCopyDelayNanos)
        let copiedText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if copiedText == sentinel {
            return (snapshot, "")
        }
        return (snapshot, copiedText)
    }

    // MARK: - Selection rewrite

    private func beginRewriteFromVoiceInstruction() {
        guard !isSelectionRewriteInProgress else { return }
        guard !dictation.isCaptureActive else { return }
        guard !PermissionController.shared.checkAndPromptIfNeededForRewrite() else {
            return
        }

        pendingRewriteTargetApp = NSWorkspace.shared.frontmostApplication
        isSelectionRewriteInProgress = true
        isCapturingRewriteInstruction = true
        isPersistentCaptureLocked = false
        overlay.setLocked(false)
        overlay.showListening(mode: .rewrite)
        dictation.start()
        updateStatusIcon(isRecording: true)
    }

    private func finishRewriteInstructionCaptureIfNeeded() {
        guard isCapturingRewriteInstruction else { return }
        isCapturingRewriteInstruction = false
        isPersistentCaptureLocked = false
        overlay.setLocked(false)

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

    private func handleOverlayAccessoryButtonTap() {
        guard dictation.isCaptureActive else { return }

        if isPersistentCaptureLocked {
            stopPersistentCapture()
            return
        }

        isPersistentCaptureLocked = true
        overlay.setLocked(true)
    }

    private func stopPersistentCapture() {
        guard dictation.isCaptureActive else {
            isPersistentCaptureLocked = false
            overlay.setLocked(false)
            return
        }

        isPersistentCaptureLocked = false
        overlay.setLocked(false)
        fnIsDown = false

        if isCapturingRewriteInstruction {
            finishRewriteInstructionCaptureIfNeeded()
        } else {
            handleFnReleased()
        }
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

        targetApp.activate(options: [])
        overlay.showListening(mode: .rewrite)
        try? await Task.sleep(nanoseconds: Constants.rewriteCopyDelayNanos)

        let contextResolver = ContextResolver()
        let rewriteFieldContext = contextResolver.resolve()
        let rewriteMode = rewriteFieldContext.map { contextResolver.draftMode(for: $0) }

        let (snapshot, copiedSelection) = await readSelectedTextFromFocusedApp()
        let usesQuickReplyContext = copiedSelection.isEmpty && !quickReplyContextText.isEmpty
        let sourceText = usesQuickReplyContext ? quickReplyContextText : copiedSelection

        guard !sourceText.isEmpty else {
            restorePasteboardSnapshot(snapshot)
            presentRewriteError("No selected text found. Highlight text, or save context first with \(settings.shortcutTriggerKey.saveReplyContextShortcut).")
            return
        }

        let rewriteTargetLanguage = inferredRewriteTargetLanguage(from: sourceText)
        if let rewriteTargetLanguage {
            print("✏️ rewrite target lang:", rewriteTargetLanguage)
        }
        let replyMemories = AppSettings.shared.matchingReplyMemories(
            for: sourceText,
            instruction: instruction
        )
        if !replyMemories.isEmpty {
            print("✏️ rewrite memory matches:", replyMemories.map(\.title).joined(separator: ", "))
        }

        do {
            let result = try await AIClient.shared.rewrite(
                text: sourceText,
                instruction: instruction,
                targetLanguageOverride: rewriteTargetLanguage,
                replyMemories: replyMemories,
                draftReplyFromContext: usesQuickReplyContext,
                modeOverride: rewriteMode
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
            if usesQuickReplyContext {
                quickReplyContextText = ""
            }
            print("✏️ rewrite done | chars:", sourceText.count, "->", rewritten.count, usesQuickReplyContext ? "(from saved context)" : "")
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
        AppLogStore.shared.record(.warning, "Rewrite failed", metadata: ["message": message])
        if message.localizedCaseInsensitiveContains("Accessibility permission") {
            PermissionController.shared.show(type: .accessibility)
        } else {
            NSSound.beep()
        }
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
        backendStatusItem?.title = online
            ? "Backend: ✅ online"
            : "Backend: ⚠️ offline"
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusButton()

        let menu = NSMenu()

        let backendItem = NSMenuItem(title: "Sjekker backend…", action: nil, keyEquivalent: "")
        backendStatusItem = backendItem
        menu.addItem(backendItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Home", action: #selector(openHome)))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSectionHeader(title: "Preferences"))
        let aiItem = makeMenuItem(title: "AI Polish: ON", action: #selector(toggleAI))
        menu.addItem(aiItem)
        aiMenuItem = aiItem

        menu.addItem(makeMicrophoneRootMenuItem())
        menu.addItem(makeLanguagesRootMenuItem())
        menu.addItem(makeStyleRootMenuItem())
        menu.addItem(makeInterpretationRootMenuItem())

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSectionHeader(title: "Account"))
        let signOutItem = makeMenuItem(title: "Sign out", action: #selector(signOut))
        signOutMenuItem = signOutItem
        menu.addItem(signOutItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        refreshSignOutMenuState()
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

    private func makeSectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeMicrophoneRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let microphoneMenu = NSMenu(title: "Microphone")
        microphoneMenuItems.removeAll()

        for microphone in MicrophoneCatalog.availableOptions() {
            let item = makeMenuItem(title: microphone.name, action: #selector(selectMicrophone(_:)))
            item.representedObject = microphone.id
            microphoneMenu.addItem(item)
            microphoneMenuItems[microphone.id] = item
        }

        rootItem.submenu = microphoneMenu
        return rootItem
    }

    private func makeLanguagesRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Languages", action: nil, keyEquivalent: "")
        let languagesMenu = NSMenu(title: "Languages")
        languagesMenu.addItem(makeLanguageRootMenuItem())
        languagesMenu.addItem(makeTranslationRootMenuItem())
        rootItem.submenu = languagesMenu
        return rootItem
    }

    private func makeLanguageRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Input Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: "Input Language")
        languageMenuItems.removeAll()

        for language in AppLanguage.allCases {
            let item = makeMenuItem(title: language.pickerMenuLabel, action: #selector(selectLanguage(_:)))
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

    private func makeInterpretationRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Forståelse", action: nil, keyEquivalent: "")
        let interpretationMenu = NSMenu(title: "Forståelse")
        interpretationMenuItems.removeAll()

        for interpretationLevel in InterpretationLevel.allCases {
            let item = makeMenuItem(title: interpretationLevel.label, action: #selector(selectInterpretationLevel(_:)))
            item.representedObject = interpretationLevel.rawValue
            item.toolTip = interpretationLevel.description
            interpretationMenu.addItem(item)
            interpretationMenuItems[interpretationLevel] = item
        }

        rootItem.submenu = interpretationMenu
        return rootItem
    }

    private func makeTranslationRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Translate To", action: nil, keyEquivalent: "")
        let translationMenu = NSMenu(title: "Translate To")
        translationMenuItems.removeAll()

        for language in AppLanguage.allCases {
            let item = makeMenuItem(title: language.pickerMenuLabel, action: #selector(selectTranslationTarget(_:)))
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

    private func refreshMicrophoneMenuState() {
        let selectedID = settings.selectedMicrophoneUID
        for (id, item) in microphoneMenuItems {
            item.state = selectedID == id ? .on : .off
        }
    }

    private func refreshSignOutMenuState() {
        signOutMenuItem?.isEnabled = settings.hasAuthenticatedSession
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

    private func refreshInterpretationMenuState() {
        for (interpretationLevel, item) in interpretationMenuItems {
            item.state = settings.interpretationLevel == interpretationLevel ? .on : .off
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

    private func applyInterpretationLevel(_ interpretationLevel: InterpretationLevel, persist: Bool) {
        if persist {
            settings.interpretationLevel = interpretationLevel
        }
        dictation.setInterpretationLevel(interpretationLevel)
        refreshInterpretationMenuState()
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

    @objc private func openHome() {
        NSApp.activate(ignoringOtherApps: true)
        configureHomeWindowBehavior()
        for window in NSApp.windows {
            if isHomeWindow(window) {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
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

    @objc private func signOut() {
        settings.signOutSupabaseSession()
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

    @objc private func selectInterpretationLevel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let interpretationLevel = InterpretationLevel(rawValue: raw)
        else { return }
        applyInterpretationLevel(interpretationLevel, persist: true)
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let microphoneID = sender.representedObject as? String else { return }
        settings.selectedMicrophoneUID = microphoneID
        refreshMicrophoneMenuState()
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

    private func configureHomeWindowBehavior() {
        for window in NSApp.windows where isHomeWindow(window) {
            window.delegate = self
        }
    }

    private func isHomeWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "home" || window.title.contains("FlowSpeak")
    }
}
