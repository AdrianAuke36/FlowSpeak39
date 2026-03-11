import Cocoa
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Combine
import NaturalLanguage

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private final class QuickReplyEventTapContext {
        weak var appDelegate: AppDelegate?

        init(appDelegate: AppDelegate) {
            self.appDelegate = appDelegate
        }
    }

    private enum MenuBarVisualState {
        case normal
        case warning
        case recording
    }

    private enum Constants {
        static let backendPollIntervalNanos: UInt64 = 15_000_000_000
        static let startupPrewarmDelayNanos: UInt64 = 750_000_000
        static let rewriteCopyDelayNanos: UInt64 = 170_000_000
        static let quickReplyCopyDelayNanos: UInt64 = 260_000_000
        static let quickReplyWaitReleaseStepNanos: UInt64 = 35_000_000
        static let quickReplyWaitReleaseMaxSteps: Int = 8
        static let rewritePasteDelayNanos: UInt64 = 120_000_000
        static let fnDictationStartDelayNanos: UInt64 = 120_000_000
        static let fnReleaseGraceNanos: UInt64 = 220_000_000
        static let triggerPostReleaseSuppressionSeconds: TimeInterval = 0.20
        static let quickReplyCaptureMinInterval: TimeInterval = 0.55
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
    private var quickReplyKeyEventTap: CFMachPort?
    private var quickReplyKeyEventSource: CFRunLoopSource?
    private var quickReplyKeyEventTapContext: Unmanaged<QuickReplyEventTapContext>?

    private var backendStatusItem: NSMenuItem?
    private var aiMenuItem: NSMenuItem?
    private var signOutMenuItem: NSMenuItem?
    private var microphoneMenuItems: [String: NSMenuItem] = [:]
    private var languageMenuItems: [AppLanguage: NSMenuItem] = [:]
    private var translationMenuItems: [AppLanguage: NSMenuItem] = [:]
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
    private var lastRewriteInstructionPartial: String = ""
    private var quickReplyContextText: String = ""
    private var hasPendingQuickReplyContextRewrite: Bool = false
    private var lastQuickReplyCaptureAt: Date = .distantPast
    private var triggerShortcutSuppressionUntil: Date = .distantPast
    private var pendingReleaseToInsertStartedAt: Date?
    private var pendingReleaseToInsertMode: String = "dictate"

    private func menuUI(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogStore.shared.record(.info, "App launched")
        NSApp.setActivationPolicy(.accessory)

        configureDictationCallbacks()

        // Be om Accessibility-tillatelse med dialog hvis ikke gitt.
        // Use CFBoolean to avoid unnecessary Swift bridging churn on launch.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: kCFBooleanTrue] as CFDictionary
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
        applyInterpretationLevel(settings.interpretationLevel, persist: false)
        applyBackendConfiguration(
            baseURL: settings.backendBaseURL,
            token: settings.backendToken,
            persist: false
        )
        refreshMicrophoneMenuState()
        refreshLanguageMenuState()
        refreshTranslationMenuState()
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
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Constants.startupPrewarmDelayNanos)
            self.dictation.prewarmLocalCapturePipeline()
            await AIClient.shared.prewarmDraftPipelineIfNeeded()
        }

        DispatchQueue.main.async { [weak self] in
            self?.configureHomeWindowBehavior()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureHomeWindowBehavior()
        ensureKeyboardMonitors()
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
        teardownKeyboardMonitors()
    }

    deinit {
        teardownKeyboardMonitors()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isHomeWindow(sender) else { return true }
        sender.orderOut(nil)
        return false
    }

    private func observeSettingsChanges() {
        settings.$interfaceLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        settings.$appLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyLanguage(language, persist: false)
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

        settings.$statusMenuAdvancedModeEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)
    }

    private func configureDictationCallbacks() {
        dictation.onPartial = { [weak self] text in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.isSelectionRewriteInProgress {
                    self.lastRewriteInstructionPartial = text
                }
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
                self.logReleaseToInsertLatencyIfNeeded()
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
        teardownKeyboardMonitors()
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
        setupQuickReplyShortcutSuppressionTap()
    }

    private func teardownKeyboardMonitors() {
        teardownQuickReplyShortcutSuppressionTap()
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

    private func ensureKeyboardMonitors() {
        let hasAllMonitors =
            globalFlagsMonitor != nil &&
            localFlagsMonitor != nil &&
            globalKeyDownMonitor != nil &&
            localKeyDownMonitor != nil
        guard !hasAllMonitors else { return }

        AppLogStore.shared.record(.warning, "Keyboard monitors missing, reinitializing")
        setupFnKeyTap()
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
        // Quick-reply key handling is primarily done by the CGEvent tap.
        // Avoid double-triggering from NSEvent monitors when tap is active.
        if quickReplyKeyEventTap != nil {
            return false
        }
        if event.isARepeat {
            return false
        }
        if !selectedTriggerIsDown || shiftIsDown || controlIsDown {
            return false
        }

        guard isQuickReplyContextShortcut(event) else {
            return false
        }

        guard shouldAcceptQuickReplyTrigger() else {
            return true
        }
        triggerQuickReplyContextCapture()
        return true
    }

    private func setupQuickReplyShortcutSuppressionTap() {
        guard quickReplyKeyEventTap == nil else { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<QuickReplyEventTapContext>.fromOpaque(refcon).takeUnretainedValue()
            guard let app = context.appDelegate else {
                return Unmanaged.passUnretained(event)
            }
            return app.handleQuickReplyEventTap(proxy: proxy, type: type, event: event)
        }

        let contextRef = Unmanaged.passRetained(QuickReplyEventTapContext(appDelegate: self))
        quickReplyKeyEventTapContext = contextRef
        let refcon = UnsafeMutableRawPointer(contextRef.toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: refcon
        ) else {
            quickReplyKeyEventTapContext?.release()
            quickReplyKeyEventTapContext = nil
            AppLogStore.shared.record(.info, "Quick reply suppression tap unavailable; using monitor fallback")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            quickReplyKeyEventTapContext?.release()
            quickReplyKeyEventTapContext = nil
            AppLogStore.shared.record(.info, "Quick reply suppression source unavailable; using monitor fallback")
            return
        }

        quickReplyKeyEventTap = tap
        quickReplyKeyEventSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func teardownQuickReplyShortcutSuppressionTap() {
        if let source = quickReplyKeyEventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            quickReplyKeyEventSource = nil
        }
        if let tap = quickReplyKeyEventTap {
            CFMachPortInvalidate(tap)
            quickReplyKeyEventTap = nil
        }
        if let context = quickReplyKeyEventTapContext {
            context.release()
            quickReplyKeyEventTapContext = nil
        }
    }

    private func handleQuickReplyEventTap(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = quickReplyKeyEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        if settings.isShortcutCaptureActive {
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        if shouldSuppressTriggerShortcutsDuringCapture(event: event, flags: flags) {
            return nil
        }
        guard isSelectedTriggerDownForQuickReplyEvent(flags: flags) else {
            return Unmanaged.passUnretained(event)
        }
        guard isQuickReplyContextShortcut(event) else {
            if flags.contains(.maskShift) || flags.contains(.maskControl) {
                return Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard shouldAcceptQuickReplyTrigger() else {
            return nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.triggerQuickReplyContextCapture()
        }
        return nil
    }

    private func shouldSuppressTriggerShortcutsDuringCapture(event: CGEvent, flags _: CGEventFlags) -> Bool {
        // Keep the save-context shortcut available while trigger key is held.
        if isQuickReplyContextShortcut(event) {
            return false
        }

        // Suppress only while trigger is physically down (or immediately after release)
        // to avoid leaking browser/app shortcuts, but do not block internal rewrite copy/paste.
        // Only use tracked physical modifier state (not event.flags), otherwise synthetic
        // command combos used by rewrite (Cmd+C / Cmd+V) can be suppressed by mistake.
        let triggerFlowActive = selectedTriggerIsDown || fnIsDown || Date() < triggerShortcutSuppressionUntil
        guard triggerFlowActive else { return false }
        return true
    }

    private func isSelectedTriggerDownForQuickReplyEvent(flags: CGEventFlags) -> Bool {
        switch settings.shortcutTriggerKey {
        case .function:
            return flags.contains(.maskSecondaryFn) || functionModifierIsDown
        case .leftOption:
            return flags.contains(.maskAlternate) || leftOptionModifierIsDown
        case .rightOption:
            return flags.contains(.maskAlternate) || rightOptionModifierIsDown
        case .leftCommand:
            return flags.contains(.maskCommand) || leftCommandModifierIsDown
        case .rightCommand:
            return flags.contains(.maskCommand) || rightCommandModifierIsDown
        }
    }

    private func isQuickReplyContextShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_ANSI_K) {
            return true
        }
        let chars = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return chars == "k"
    }

    private func isQuickReplyContextShortcut(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_K) {
            return true
        }
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }
        return isQuickReplyContextShortcut(nsEvent)
    }

    private func shouldAcceptQuickReplyTrigger() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastQuickReplyCaptureAt) < Constants.quickReplyCaptureMinInterval {
            return false
        }
        lastQuickReplyCaptureAt = now
        return true
    }

    private func triggerQuickReplyContextCapture() {
        guard settings.hasAuthenticatedSession else {
            Task { @MainActor in
                settings.requestSignedOutPopup()
            }
            openHome()
            return
        }
        cancelPendingFnStart()
        if dictation.isCaptureActive {
            dictation.cancelCapture()
            isPersistentCaptureLocked = false
            overlay.setLocked(false)
            overlay.hide()
            clearPendingReleaseToInsertLatency()
            updateStatusIcon(isRecording: false)
        }
        Task { @MainActor [weak self] in
            await self?.captureQuickReplyContext()
        }
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

        if fnDown && controlDown && !didConsumeFnHoldForRewriteCombo && !isSelectionRewriteInProgress {
            // If dictation already started (timing race), switch cleanly into rewrite capture.
            if dictation.isCaptureActive {
                dictation.cancelCapture()
                overlay.hide()
                clearPendingReleaseToInsertLatency()
                updateStatusIcon(isRecording: false)
            }
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
            triggerShortcutSuppressionUntil = Date().addingTimeInterval(Constants.triggerPostReleaseSuppressionSeconds)
            cancelPendingFnStart()
            didSetTranslationOverrideInCurrentFnHold = false
            if didConsumeFnHoldForRewriteCombo {
                clearPendingReleaseToInsertLatency()
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
                clearPendingReleaseToInsertLatency()
                return
            }
            if dictation.isCaptureActive {
                beginReleaseToInsertLatency(
                    mode: (didSetTranslationOverrideInCurrentFnHold || shiftDown) ? "translate" : "dictate"
                )
            } else {
                clearPendingReleaseToInsertLatency()
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
        triggerShortcutSuppressionUntil = .distantPast
        pendingRewriteTargetApp = nil
        clearPendingReleaseToInsertLatency()
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
            // Use the actual modifier flags instead of toggling to avoid
            // false up/down transitions in some apps (for example Notes).
            leftOptionModifierIsDown = flags.contains(.option)
        } else if event.type == .flagsChanged && event.keyCode == UInt16(kVK_RightOption) {
            rightOptionModifierIsDown = flags.contains(.option)
        } else if event.type == .flagsChanged && event.keyCode == UInt16(kVK_Command) {
            leftCommandModifierIsDown = flags.contains(.command)
        } else if event.type == .flagsChanged && event.keyCode == UInt16(kVK_RightCommand) {
            rightCommandModifierIsDown = flags.contains(.command)
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
        clearPendingReleaseToInsertLatency()
        guard settings.hasAuthenticatedSession else {
            Task { @MainActor in
                settings.requestSignedOutPopup()
            }
            openHome()
            updateStatusIcon(isRecording: false)
            return
        }
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
        dictation.start(mode: .dictation)
        updateStatusIcon(isRecording: true)
    }

    private func handleFnReleased() {
        guard dictation.isCaptureActive else {
            clearPendingReleaseToInsertLatency()
            return
        }
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
        let contextResolver = ContextResolver()

        let targetApp = NSWorkspace.shared.frontmostApplication
        targetApp?.activate(options: [])
        await waitForQuickReplyTriggerReleaseIfNeeded()
        try? await Task.sleep(nanoseconds: Constants.quickReplyCopyDelayNanos)

        let (snapshot, selectedText) = await readSelectedTextFromFocusedApp(copyDelayNanos: Constants.quickReplyCopyDelayNanos)
        defer { restorePasteboardSnapshot(snapshot) }

        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let axSelection = contextResolver
            .selectedTextForQuickReply(maxLength: 9000)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chosenText: String
        let source: String
        if !trimmedSelection.isEmpty {
            chosenText = trimmedSelection
            source = "selection_copy"
        } else if !axSelection.isEmpty {
            chosenText = axSelection
            source = "selection_ax"
        } else {
            chosenText = ""
            source = "none"
        }

        guard !chosenText.isEmpty else {
            NSSound.beep()
            overlay.showSaveFailedToast()
            AppLogStore.shared.record(.warning, "Quick reply context capture failed", metadata: ["reason": "No selected text"])
            return
        }

        quickReplyContextText = chosenText
        hasPendingQuickReplyContextRewrite = true
        playQuickReplySavedSound()
        overlay.showSavedToast()
        AppLogStore.shared.record(.info, "Quick reply context saved", metadata: ["chars": "\(chosenText.count)", "source": source])
        print("💾 quick reply context saved | chars:", chosenText.count, "| source:", source)
    }

    @MainActor
    private func waitForQuickReplyTriggerReleaseIfNeeded() async {
        var steps = 0
        while selectedTriggerIsDown && steps < Constants.quickReplyWaitReleaseMaxSteps {
            steps += 1
            try? await Task.sleep(nanoseconds: Constants.quickReplyWaitReleaseStepNanos)
        }
    }

    private func playQuickReplySavedSound() {
        if let sound = NSSound(named: "Glass") ?? NSSound(named: "Hero") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    @MainActor
    private func readSelectedTextFromFocusedApp(copyDelayNanos: UInt64) async -> (PasteboardSnapshot, String) {
        let snapshot = capturePasteboardSnapshot()
        let sentinel = "__bluespeak_selection__\(UUID().uuidString)"
        writeStringToPasteboard(sentinel)
        sendCmdC()
        try? await Task.sleep(nanoseconds: copyDelayNanos)
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
        lastRewriteInstructionPartial = ""
        isSelectionRewriteInProgress = true
        isCapturingRewriteInstruction = true
        isPersistentCaptureLocked = false
        AppLogStore.shared.record(.info, "Rewrite instruction capture started")
        overlay.setLocked(false)
        overlay.showListening(mode: .rewrite)
        dictation.start(mode: .rewriteInstruction)
        updateStatusIcon(isRecording: true)
    }

    private func finishRewriteInstructionCaptureIfNeeded() {
        guard isCapturingRewriteInstruction else { return }
        isCapturingRewriteInstruction = false
        isPersistentCaptureLocked = false
        overlay.setLocked(false)

        var instruction = dictation
            .stopAndCaptureInstruction()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if instruction.isEmpty {
            let fallback = lastRewriteInstructionPartial.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                instruction = fallback
                AppLogStore.shared.record(
                    .info,
                    "Rewrite instruction fallback used",
                    metadata: ["chars": "\(fallback.count)"]
                )
            }
        }
        lastRewriteInstructionPartial = ""
        updateStatusIcon(isRecording: false)
        AppLogStore.shared.record(
            .info,
            "Rewrite instruction captured",
            metadata: ["chars": "\(instruction.count)"]
        )

        guard !instruction.isEmpty else {
            AppLogStore.shared.record(.warning, "Rewrite instruction capture failed", metadata: ["reason": "Empty instruction"])
            presentRewriteError("No rewrite instruction captured. Hold \(settings.shortcutTriggerKey.rewriteShortcut), speak your instruction, then release.")
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
            clearPendingReleaseToInsertLatency()
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

    private func beginReleaseToInsertLatency(mode: String) {
        pendingReleaseToInsertStartedAt = Date()
        pendingReleaseToInsertMode = mode
    }

    private func clearPendingReleaseToInsertLatency() {
        pendingReleaseToInsertStartedAt = nil
        pendingReleaseToInsertMode = "dictate"
    }

    private func logReleaseToInsertLatencyIfNeeded() {
        guard let startedAt = pendingReleaseToInsertStartedAt else { return }
        let elapsedMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        let mode = pendingReleaseToInsertMode
        clearPendingReleaseToInsertLatency()
        AppLogStore.shared.record(
            .info,
            "STT release-to-insert",
            metadata: [
                "provider": dictation.activeSTTProviderLogValue,
                "ms": "\(elapsedMs)",
                "mode": mode,
                "trigger": settings.shortcutTriggerKey.rawValue
            ]
        )
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

        let (snapshot, copiedSelection) = await readSelectedTextFromFocusedApp(copyDelayNanos: Constants.rewriteCopyDelayNanos)
        let hasSavedQuickReplyContext = !quickReplyContextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasSavedQuickReplyContext {
            hasPendingQuickReplyContextRewrite = false
        }
        let shouldPrioritizeSavedContext = hasPendingQuickReplyContextRewrite && hasSavedQuickReplyContext
        let usesQuickReplyContext = shouldPrioritizeSavedContext || (copiedSelection.isEmpty && hasSavedQuickReplyContext)
        let sourceText: String = {
            if usesQuickReplyContext { return quickReplyContextText }
            return copiedSelection
        }()
        let contextIndicatesEmailReply = contextLooksLikeEmailReplyField(rewriteFieldContext) || textLooksLikeEmailThread(sourceText)
        let forcedEmailModeForQuickReply = usesQuickReplyContext &&
            (rewriteMode == nil || rewriteMode == .generic) &&
            contextIndicatesEmailReply
        let effectiveRewriteMode: DraftMode? = forcedEmailModeForQuickReply ? .emailBody : rewriteMode
        if forcedEmailModeForQuickReply {
            AppLogStore.shared.record(
                .info,
                "Rewrite forced email mode",
                metadata: ["source": contextLooksLikeEmailReplyField(rewriteFieldContext) ? "field_context" : "saved_context"]
            )
        }
        let emailRecipientHint = usesQuickReplyContext
            ? resolvedEmailRecipientHint(
                sourceText: sourceText,
                fallbackHint: rewriteFieldContext?.emailRecipientHint
            )
            : nil

        guard !sourceText.isEmpty else {
            restorePasteboardSnapshot(snapshot)
            presentRewriteError("No text found. Highlight text first, or save selected text with \(settings.shortcutTriggerKey.saveReplyContextShortcut).")
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
                modeOverride: effectiveRewriteMode,
                emailRecipientHint: emailRecipientHint
            )
            let rewritten = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewritten.isEmpty else {
                restorePasteboardSnapshot(snapshot)
                presentRewriteError("AI returned empty text.")
                return
            }

            let textToInsert: String
            textToInsert = rewritten

            writeStringToPasteboard(textToInsert)
            sendCmdV()
            try? await Task.sleep(nanoseconds: Constants.rewritePasteDelayNanos)
            restorePasteboardSnapshot(snapshot)
            if usesQuickReplyContext {
                quickReplyContextText = ""
                hasPendingQuickReplyContextRewrite = false
            }
            print(
                "✏️ rewrite done | chars:",
                sourceText.count,
                "->",
                rewritten.count,
                usesQuickReplyContext ? "(from saved context)" : ""
            )
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

    private func resolvedEmailRecipientHint(sourceText: String, fallbackHint: String?) -> String? {
        if let extracted = extractEmailReplySenderName(from: sourceText) {
            return extracted
        }
        guard let fallbackHint else { return nil }
        return sanitizeEmailRecipientCandidate(fallbackHint)
    }

    private func extractEmailReplySenderName(from text: String) -> String? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.prefix(12) {
            let compact = line
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let angleStart = compact.firstIndex(of: "<"),
               compact.contains(">"),
               angleStart > compact.startIndex {
                let rawName = String(compact[..<angleStart])
                if let sanitized = sanitizeEmailRecipientCandidate(rawName) {
                    return sanitized
                }
            }

            let lower = compact.lowercased()
            if lower.hasPrefix("from:") || lower.hasPrefix("fra:") {
                var rawName = compact
                if let colonIndex = rawName.firstIndex(of: ":") {
                    rawName = String(rawName[rawName.index(after: colonIndex)...])
                }
                if let angleStart = rawName.firstIndex(of: "<") {
                    rawName = String(rawName[..<angleStart])
                }
                if let sanitized = sanitizeEmailRecipientCandidate(rawName) {
                    return sanitized
                }
            }
        }

        return nil
    }

    private func sanitizeEmailRecipientCandidate(_ raw: String) -> String? {
        let cleaned = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))
        guard !cleaned.isEmpty, cleaned.count <= 60 else { return nil }
        guard cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }

        let lower = cleaned.lowercased()
        let blockedTerms = [
            "send", "sende", "subject", "emne", "mottaker", "recipient", "compose", "ny melding",
            "new message", "sans serif", "flow", "bluespeak", "settings", "home", "continue",
            "til", "cc", "bcc", "inbox", "innboks",
            "bruk", "bruker", "bruk app i fokus", "use focused app", "focused app", "fokus", "focus"
        ]
        if blockedTerms.contains(where: { lower == $0 || lower.contains($0) }) {
            return nil
        }

        let words = cleaned.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 4 else { return nil }

        let lettersOnly = CharacterSet.letters.union(CharacterSet(charactersIn: "-'"))
        guard words.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(lettersOnly.contains) }) else {
            return nil
        }

        let capitalizedWords = words.filter { word in
            guard let first = word.unicodeScalars.first else { return false }
            return CharacterSet.uppercaseLetters.contains(first)
        }.count

        if words.count == 1 {
            return capitalizedWords == 1 ? cleaned : nil
        }
        return capitalizedWords >= 2 ? cleaned : nil
    }

    private func contextLooksLikeEmailReplyField(_ context: FieldContext?) -> Bool {
        guard let context else { return false }

        let bundle = context.bundleId.lowercased()
        if bundle == "com.apple.mail" || bundle.contains("outlook") {
            return true
        }

        let url = (context.browserURL ?? "").lowercased()
        if url.contains("mail.google.com") || url.contains("outlook.live.com") || url.contains("outlook.office.com") {
            return true
        }

        let blob = [
            context.axDescription,
            context.axHelp,
            context.axTitle,
            context.axPlaceholder
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let hints = [
            "e-post", "email", "compose", "new message", "reply", "svar",
            "mottaker", "recipient", "subject", "emne", "message body",
            "gmail", "outlook", "to", "cc", "bcc"
        ]
        return hints.contains { blob.contains($0) }
    }

    private func textLooksLikeEmailThread(_ text: String) -> Bool {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }

        let lower = raw.lowercased()
        if lower.contains("med vennlig hilsen") || lower.contains("vennlig hilsen") || lower.contains("best regards") {
            return true
        }
        if lower.range(of: #"\b(fra|from|til|to|emne|subject|cc|bcc)\s*:"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b"#, options: .regularExpression) != nil {
            return true
        }

        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }

        if lines[0].range(of: #"^(re|sv|fw|fwd)\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if lines[0].range(of: #"^(hei|hello|hi|dear|kjære)\b"#, options: [.regularExpression, .caseInsensitive]) != nil && lines.count >= 3 {
            return true
        }
        if lines.prefix(6).contains(where: { $0.range(of: #"^"?[^"<]{2,120}"?\s*<[^>]+>$"#, options: .regularExpression) != nil }) {
            return true
        }
        if lines.prefix(6).contains(where: { $0.range(of: #"^(til|to)\s+\S+"#, options: [.regularExpression, .caseInsensitive]) != nil }) {
            return true
        }

        return false
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
            ? menuUI("Backend: ✅ online", "Backend: ✅ online")
            : menuUI("Backend: ⚠️ offline", "Backend: ⚠️ offline")
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusButton()
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        let backendItem = NSMenuItem(title: menuUI("Sjekker backend…", "Checking backend…"), action: nil, keyEquivalent: "")
        backendStatusItem = backendItem
        menu.addItem(backendItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: menuUI("Hjem", "Home"), action: #selector(openHome)))

        menu.addItem(NSMenuItem.separator())
        if settings.statusMenuAdvancedModeEnabled {
            menu.addItem(makeSectionHeader(title: menuUI("Innstillinger", "Preferences")))
            let aiItem = makeMenuItem(title: menuUI("AI Polish: PÅ", "AI Polish: ON"), action: #selector(toggleAI))
            menu.addItem(aiItem)
            aiMenuItem = aiItem

            menu.addItem(makeMicrophoneRootMenuItem())
            menu.addItem(makeLanguagesRootMenuItem())
            menu.addItem(makeInterpretationRootMenuItem())
        } else {
            menu.addItem(makeSectionHeader(title: menuUI("Hurtig", "Quick")))
            menu.addItem(makeMicrophoneRootMenuItem())
            menu.addItem(makeLanguagesRootMenuItem())
            menu.addItem(makeAdvancedPreferencesRootMenuItem())
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSectionHeader(title: menuUI("Konto", "Account")))
        let signOutItem = makeMenuItem(title: menuUI("Logg ut", "Sign out"), action: #selector(signOut))
        signOutMenuItem = signOutItem
        menu.addItem(signOutItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: menuUI("Avslutt", "Quit"), action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        updateBackendMenuItem(online: backendOnline)
        refreshSignOutMenuState()
        refreshAIMenuTitle()
        refreshMicrophoneMenuState()
        refreshLanguageMenuState()
        refreshTranslationMenuState()
        refreshInterpretationMenuState()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = normalStatusImage
        button.toolTip = "BlueSpeak"
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

    private func makeAdvancedPreferencesRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: menuUI("Avansert", "Advanced"), action: nil, keyEquivalent: "")
        let advancedMenu = NSMenu(title: menuUI("Avansert", "Advanced"))

        let aiItem = makeMenuItem(title: menuUI("AI Polish: PÅ", "AI Polish: ON"), action: #selector(toggleAI))
        advancedMenu.addItem(aiItem)
        aiMenuItem = aiItem

        advancedMenu.addItem(makeInterpretationRootMenuItem())
        rootItem.submenu = advancedMenu
        return rootItem
    }

    private func makeMicrophoneRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: menuUI("Mikrofon", "Microphone"), action: nil, keyEquivalent: "")
        let microphoneMenu = NSMenu(title: menuUI("Mikrofon", "Microphone"))
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
        let rootItem = NSMenuItem(title: menuUI("Språk", "Languages"), action: nil, keyEquivalent: "")
        let languagesMenu = NSMenu(title: menuUI("Språk", "Languages"))
        languagesMenu.addItem(makeLanguageRootMenuItem())
        languagesMenu.addItem(makeTranslationRootMenuItem())
        rootItem.submenu = languagesMenu
        return rootItem
    }

    private func makeLanguageRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: menuUI("Inndataspråk", "Input Language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: menuUI("Inndataspråk", "Input Language"))
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

    private func makeInterpretationRootMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: menuUI("Forståelse", "Interpretation"), action: nil, keyEquivalent: "")
        let interpretationMenu = NSMenu(title: menuUI("Forståelse", "Interpretation"))
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
        let rootItem = NSMenuItem(title: menuUI("Oversett til", "Translate To"), action: nil, keyEquivalent: "")
        let translationMenu = NSMenu(title: menuUI("Oversett til", "Translate To"))
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
        aiMenuItem?.title = dictation.aiEnabled
            ? menuUI("AI Polish: PÅ", "AI Polish: ON")
            : menuUI("AI Polish: AV", "AI Polish: OFF")
    }

    private func refreshMicrophoneMenuState() {
        let selectedID = settings.selectedMicrophoneUID
        for (id, item) in microphoneMenuItems {
            item.state = selectedID == id ? .on : .off
        }
    }

    private func refreshSignOutMenuState() {
        let authenticated = settings.hasAuthenticatedSession
        signOutMenuItem?.title = authenticated
            ? menuUI("Logg ut", "Sign out")
            : menuUI("Logg inn", "Sign in")
        signOutMenuItem?.action = authenticated ? #selector(signOut) : #selector(openHome)
        signOutMenuItem?.isEnabled = true
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
        window.identifier?.rawValue == "home" || window.title.contains("BlueSpeak")
    }
}
