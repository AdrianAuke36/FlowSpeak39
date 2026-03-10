import Foundation
import AVFoundation
import Speech
import AppKit
import Carbon.HIToolbox
import AudioToolbox
import CoreAudio

final class DictationController: NSObject {
    enum CaptureMode {
        case dictation
        case rewriteInstruction
    }

    private enum Timing {
        static let pasteDelay: TimeInterval = 0.08
        static let pasteCompletionDelay: TimeInterval = 0.08
        static let replaceDelay: TimeInterval = 0.03
        static let maxAIReplaceDelay: TimeInterval = 2.0
        static let maxAIReplaceDelayEmail: TimeInterval = 5.5
    }

    private enum SpeculativeConfig {
        static let minChars = 34
        static let minDeltaChars = 20
        static let minWords = 5
        static let maxRequestsPerSession = 2
        static let minInterval: TimeInterval = 1.1
        static let debounce: TimeInterval = 0.55
    }

    private enum SpeechConfig {
        static let fallbackLocale = "nb-NO"
        static let startSoundVolume: Float = 0.42
        static let audioBufferSize: AVAudioFrameCount = 4096
    }

    private enum GroqConfig {
        static let endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
        static let model = "whisper-large-v3"
        static let timeout: TimeInterval = 18
        static let sampleRateWav: Double = 16_000
        static let sampleRateAAC: Double = 44_100
        static let channelCount: Int = 1
        static let aacBitRate: Int = 64_000
    }

    private enum STTFallbackConfig {
        static let appleFailureThreshold = 3
        static let fallbackCaptureCount = 5
    }

    private enum LanguageGuard {
        static let englishGreetingPrefixes = ["hi", "hello", "dear"]
        static let englishSignoffPrefixes = ["best regards", "regards", "sincerely"]
    }

    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "org.mozilla.firefox"
    ]

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var groqRecorder: AVAudioRecorder?
    private var groqRecordingURL: URL?
    private let startSound = NSSound(named: "Pop")

    private(set) var isRecording: Bool = false
    private(set) var isStarting: Bool = false
    var isCaptureActive: Bool { isRecording || isStarting }
    private var finalText: String = ""
    private var hasReceivedTranscriptInCurrentCapture: Bool = false
    private var startTokenCounter: Int = 0
    private var expectedStartToken: Int = 0
    private var captureStartedAt: Date?
    private var captureMode: CaptureMode = .dictation
    private var activeSTTProvider: STTProvider = .appleSpeech
    private var appleConsecutiveFailures: Int = 0
    private var autoFallbackCapturesRemaining: Int = 0

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onInserted: (() -> Void)?
    var onCaptureInterrupted: ((String?) -> Void)?

    private let settings = AppSettings.shared

    var aiEnabled: Bool = true
    private let ai = AIClient.shared
    private let resolver = ContextResolver()
    private var prefetchedContext: FieldContext?
    private var speechLocaleIdentifier: String = SpeechConfig.fallbackLocale
    private var oneShotOutputLanguageOverride: String?
    private var interpretationLevel: InterpretationLevel = .balanced

    private struct SpeculativeDraft {
        let text: String
        let mode: DraftMode
        let targetLanguage: String
        let task: Task<PolishResponse, Error>
    }

    private var speculativeDraft: SpeculativeDraft?
    private var speculativeDebounceWorkItem: DispatchWorkItem?
    private var lastSpeculativeText: String = ""
    private var lastSpeculativeStartedAt: Date = .distantPast
    private var speculativeRequestsThisSession: Int = 0

    var activeSTTProviderLogValue: String {
        activeSTTProvider.providerLogValue
    }

    func prefetchContext() {
        prefetchedContext = resolver.resolve()
    }

    func setLanguage(_ language: AppLanguage) {
        speechLocaleIdentifier = language.speechLocaleIdentifier
        ai.targetLanguage = language.targetLanguageCode
        print("🌐 language:", language.menuLabel, "| speech:", speechLocaleIdentifier, "| target:", ai.targetLanguage)
    }

    func setOneShotOutputLanguageOverride(_ languageCode: String) {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        oneShotOutputLanguageOverride = normalized
        print("🌍 one-shot output target:", normalized)
    }

    func setInterpretationLevel(_ interpretationLevel: InterpretationLevel) {
        self.interpretationLevel = interpretationLevel
        ai.interpretationLevel = interpretationLevel
        print("🧠 dictation:", interpretationLevel.label)
    }

    func start(mode: CaptureMode = .dictation) {
        guard !isRecording, !isStarting else { return }
        captureMode = mode
        activeSTTProvider = selectedProvider(for: mode)
        if mode == .dictation,
           settings.sttProvider == .appleSpeech,
           activeSTTProvider == .groqWhisperLargeV3 {
            autoFallbackCapturesRemaining = max(0, autoFallbackCapturesRemaining - 1)
            AppLogStore.shared.record(
                .info,
                "STT auto-fallback active",
                metadata: [
                    "provider": activeSTTProvider.providerLogValue,
                    "remainingCaptures": "\(autoFallbackCapturesRemaining)",
                    "appleFailureStreak": "\(appleConsecutiveFailures)"
                ]
            )
        }
        resetSpeculativeState(cancel: true)
        finalText = ""
        hasReceivedTranscriptInCurrentCapture = false
        captureStartedAt = nil
        startTokenCounter += 1
        let token = startTokenCounter
        expectedStartToken = token
        isStarting = true

        switch activeSTTProvider {
        case .appleSpeech:
            startWithAppleSpeech(token: token)
        case .groqWhisperLargeV3:
            startWithGroq(token: token)
        }
    }

    private func selectedProvider(for mode: CaptureMode) -> STTProvider {
        if mode == .rewriteInstruction {
            return .appleSpeech
        }
        if settings.sttProvider == .appleSpeech,
           autoFallbackCapturesRemaining > 0,
           !settings.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .groqWhisperLargeV3
        }
        return settings.sttProvider
    }

    private func startWithAppleSpeech(token: Int) {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.shouldProceedStart(token: token) else { return }
                guard authStatus == .authorized else {
                    self.cancelPendingStart()
                    return
                }

                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard self.shouldProceedStart(token: token) else { return }
                        guard granted else {
                            self.cancelPendingStart()
                            return
                        }
                        self.startInternal(startToken: token)
                    }
                }
            }
        }
    }

    private func startWithGroq(token: Int) {
        let apiKey = settings.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            reportCaptureInterruption("Groq API key mangler. Sett den i Settings → Advanced → Backend.")
            cancelPendingStart()
            return
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                guard self.shouldProceedStart(token: token) else { return }
                guard granted else {
                    self.cancelPendingStart()
                    return
                }
                self.startGroqInternal(startToken: token)
            }
        }
    }

    func stopAndInsert() {
        if isStarting && !isRecording {
            clearOneShotOutputLanguageOverride()
            cancelPendingStart()
            finalText = ""
            hasReceivedTranscriptInCurrentCapture = false
            return
        }
        guard isRecording else { return }
        let outputLanguageOverride = consumeOneShotOutputLanguageOverride()
        stopInternal()
        speculativeDebounceWorkItem?.cancel()
        speculativeDebounceWorkItem = nil

        if activeSTTProvider == .groqWhisperLargeV3 {
            let captureDurationMs = captureStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
            captureStartedAt = nil
            let captureToken = startTokenCounter
            let recordingURL = groqRecordingURL
            groqRecordingURL = nil

            guard let recordingURL else {
                resetSpeculativeState(cancel: true)
                return
            }

            Task { [weak self] in
                guard let self else { return }
                defer { try? FileManager.default.removeItem(at: recordingURL) }

                do {
                    let raw = try await self.transcribeGroqAudioFile(recordingURL)
                    if !raw.isEmpty && captureDurationMs > 0 {
                        await MainActor.run {
                            AppLogStore.shared.record(
                                .info,
                                "STT capture finished",
                                metadata: [
                                    "provider": self.activeSTTProvider.providerLogValue,
                                    "ms": "\(captureDurationMs)",
                                    "chars": "\(raw.count)",
                                    "locale": self.speechLocaleIdentifier
                                ]
                            )
                        }
                    }

                    guard !raw.isEmpty else {
                        await MainActor.run {
                            self.resetSpeculativeState(cancel: true)
                        }
                        return
                    }

                    await MainActor.run {
                        guard captureToken == self.startTokenCounter else {
                            AppLogStore.shared.record(
                                .info,
                                "Groq STT result dropped",
                                metadata: ["reason": "new_capture_started"]
                            )
                            return
                        }
                        self.handleCapturedText(raw, outputLanguageOverride: outputLanguageOverride)
                    }
                } catch {
                    await MainActor.run {
                        AppLogStore.shared.record(
                            .warning,
                            "Groq STT failed",
                            metadata: ["error": error.localizedDescription]
                        )
                        self.reportCaptureInterruption("Groq STT failed: \(error.localizedDescription)")
                        self.resetSpeculativeState(cancel: true)
                    }
                }
            }
            return
        }

        let raw = consumeCapturedTranscript()
        let captureDurationMs = captureStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        captureStartedAt = nil
        if !raw.isEmpty && captureDurationMs > 0 {
            AppLogStore.shared.record(
                .info,
                "STT capture finished",
                metadata: [
                    "provider": "apple_speech",
                    "ms": "\(captureDurationMs)",
                    "chars": "\(raw.count)",
                    "locale": speechLocaleIdentifier
                ]
            )
        }
        guard !raw.isEmpty else {
            resetSpeculativeState(cancel: true)
            return
        }

        handleCapturedText(raw, outputLanguageOverride: outputLanguageOverride)
    }

    private func handleCapturedText(_ raw: String, outputLanguageOverride: String?) {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetSpeculativeState(cancel: true)
            return
        }
        markCaptureSuccess(for: activeSTTProvider)

        let ctx = prefetchedContext ?? resolver.resolve()
        prefetchedContext = nil
        let localDraftMode = ctx.map(resolver.draftMode) ?? .generic
        let dictMode = DictationMode(from: localDraftMode)
        let appName = ctx?.appName ?? "Unknown"
        let immediateText = localPolish(text: raw, mode: localDraftMode)
        onFinal?(immediateText)

        let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let baseInsertMode = settings.mode(for: frontBundleId)
        let immediateInsertMode = preferredImmediateInsertMode(base: baseInsertMode, bundleId: frontBundleId)
        let insertStartedAt = Date()

        // Insert first for low latency. Context/AI runs afterward.
        insertText(immediateText, insertMode: immediateInsertMode) { [weak self] in
            self?.onInserted?()
        }

        guard aiEnabled else {
            logDictation(text: immediateText, mode: dictMode, appName: appName)
            resetSpeculativeState(cancel: true)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let persistImmediate = {
                self.logDictation(text: immediateText, mode: dictMode, appName: appName)
            }
            let effectiveTargetLanguage = self.effectiveTargetLanguage(overrideCode: outputLanguageOverride)

            let localEffectiveInsertMode = self.preferredInsertMode(base: baseInsertMode, draftMode: localDraftMode)
            print("🧭 mode(local):", localDraftMode.rawValue, "| insert:", baseInsertMode.rawValue, "->", localEffectiveInsertMode.rawValue, "| immediate:", immediateInsertMode.rawValue, "| lang:", effectiveTargetLanguage, "| url:", ctx?.browserURL ?? "n/a")

            do {
                let result = try await self.fetchPolishedDraft(
                    text: immediateText,
                    mode: localDraftMode,
                    ctx: ctx,
                    targetLanguageOverride: outputLanguageOverride
                )
                let serverDraftMode = self.draftMode(from: result.appliedMode) ?? localDraftMode
                let polishedRaw = result.text.isEmpty ? immediateText : result.text
                let polished = self.localPolish(text: polishedRaw, mode: serverDraftMode)
                let finalInsertMode = self.preferredInsertMode(base: baseInsertMode, draftMode: serverDraftMode)
                let elapsed = Date().timeIntervalSince(insertStartedAt)
                let maxDelay = (serverDraftMode == .emailBody || serverDraftMode == .emailSubject)
                    ? Timing.maxAIReplaceDelayEmail
                    : Timing.maxAIReplaceDelay
                let forceReplace = self.shouldForceEmailReplace(immediate: immediateText, polished: polished, mode: serverDraftMode)

                DispatchQueue.main.async {
                    if !self.shouldAcceptAIOutput(polished, targetLanguage: effectiveTargetLanguage) {
                        print("⚠️ skip replace due language guard")
                        persistImmediate()
                        return
                    }
                    if elapsed > maxDelay && !forceReplace {
                        print("⏱️ skip replace (\(String(format: "%.2f", elapsed))s)")
                        persistImmediate()
                        return
                    }
                    if elapsed > maxDelay && forceReplace {
                        print("⏱️ force replace email signature (\(String(format: "%.2f", elapsed))s)")
                    }
                    print("🧭 mode(server):", result.appliedMode ?? "n/a", "=>", serverDraftMode.rawValue, "| lang:", effectiveTargetLanguage, "| insert:", baseInsertMode.rawValue, "->", finalInsertMode.rawValue)
                    guard polished != immediateText else {
                        persistImmediate()
                        return
                    }
                    self.onFinal?(polished)
                    self.replaceLastInserted(
                        raw: immediateText,
                        polished: polished,
                        initialInsertMode: immediateInsertMode,
                        finalInsertMode: finalInsertMode
                    )
                    self.logDictation(text: polished, mode: dictMode, appName: appName)
                }
            } catch AIClientError.cancelled {
                // Spekulativ task ble avbrutt ved ny input/start. Ikke logg som feil.
                DispatchQueue.main.async {
                    persistImmediate()
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ AI draft failed:", error.localizedDescription)
                    AppLogStore.shared.record(.warning, "AI draft failed", metadata: ["error": error.localizedDescription])
                    persistImmediate()
                    // Keep the already inserted raw text on failure.
                }
            }
        }
    }

    func stopAndCaptureInstruction() -> String {
        if isStarting && !isRecording {
            clearOneShotOutputLanguageOverride()
            cancelPendingStart()
            return consumeCapturedTranscript()
        }
        guard isRecording else {
            return consumeCapturedTranscript()
        }

        stopInternal()
        speculativeDebounceWorkItem?.cancel()
        speculativeDebounceWorkItem = nil

        let captured = consumeCapturedTranscript()
        captureStartedAt = nil
        resetSpeculativeState(cancel: true)
        return captured
    }

    func cancelCapture() {
        guard isCaptureActive else { return }
        stopInternal()
        resetSpeculativeState(cancel: true)
        finalText = ""
        hasReceivedTranscriptInCurrentCapture = false
        captureStartedAt = nil
    }

    // MARK: - Insert

    private func insertText(_ text: String, insertMode: InsertionMode, completion: (() -> Void)?) {
        switch insertMode {
        case .pasteOnly, .hybrid:
            insertViaPaste(text, completion: completion)
        case .typeOnly:
            typeText(text)
            completion?()
        }
    }

    // Gmail/web e-postfelter mister ofte linjeskift i type-mode, så vi tvinger paste for email body.
    private func preferredInsertMode(base: InsertionMode, draftMode: DraftMode) -> InsertionMode {
        if draftMode == .emailBody && base == .typeOnly {
            return .pasteOnly
        }
        return base
    }

    private func preferredImmediateInsertMode(base: InsertionMode, bundleId: String?) -> InsertionMode {
        guard base == .typeOnly, let bundleId else { return base }
        return isBrowser(bundleId) ? .pasteOnly : base
    }

    private func isBrowser(_ bundleId: String) -> Bool {
        Self.browserBundleIDs.contains(bundleId)
    }

    private func draftMode(from rawValue: String?) -> DraftMode? {
        guard let rawValue else { return nil }
        return DraftMode(rawValue: rawValue)
    }

    private func maybeStartSpeculativeDraft(with partialText: String) {
        guard aiEnabled, isRecording else { return }

        let raw = polishBasic(partialText)
        guard raw.count >= SpeculativeConfig.minChars else { return }

        let ctx = prefetchedContext ?? resolver.resolve()
        if prefetchedContext == nil { prefetchedContext = ctx }
        let mode = ctx.map(resolver.draftMode) ?? .generic
        let candidate = localPolish(text: raw, mode: mode)
        guard candidate.count >= SpeculativeConfig.minChars else { return }
        guard wordCount(candidate) >= SpeculativeConfig.minWords else { return }

        if let existing = speculativeDraft,
           existing.text == candidate,
           existing.mode == mode,
           existing.targetLanguage.caseInsensitiveCompare(effectiveTargetLanguage(overrideCode: oneShotOutputLanguageOverride)) == .orderedSame {
            return
        }

        let now = Date()
        let delta = abs(candidate.count - lastSpeculativeText.count)
        let sentenceEnded = candidate.last.map { ".!?".contains($0) } ?? false
        if now.timeIntervalSince(lastSpeculativeStartedAt) < SpeculativeConfig.minInterval && !sentenceEnded {
            return
        }
        if !lastSpeculativeText.isEmpty && delta < SpeculativeConfig.minDeltaChars && !sentenceEnded {
            return
        }
        guard speculativeRequestsThisSession < SpeculativeConfig.maxRequestsPerSession else { return }

        speculativeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.aiEnabled, self.isRecording else { return }
            guard self.speculativeRequestsThisSession < SpeculativeConfig.maxRequestsPerSession else { return }
            let targetLanguageOverride = self.oneShotOutputLanguageOverride
            let effectiveTargetLanguage = self.effectiveTargetLanguage(overrideCode: targetLanguageOverride)
            if let existing = self.speculativeDraft,
               existing.text == candidate,
               existing.mode == mode,
               existing.targetLanguage.caseInsensitiveCompare(effectiveTargetLanguage) == .orderedSame {
                return
            }

            self.speculativeDraft?.task.cancel()
            self.speculativeRequestsThisSession += 1
            self.speculativeDraft = SpeculativeDraft(
                text: candidate,
                mode: mode,
                targetLanguage: effectiveTargetLanguage,
                task: Task { [ai] in
                    try await ai.draft(
                        text: candidate,
                        mode: mode,
                        ctx: ctx,
                        targetLanguageOverride: effectiveTargetLanguage
                    )
                }
            )

            self.lastSpeculativeText = candidate
            self.lastSpeculativeStartedAt = Date()
            print("⚡️ speculative:", mode.rawValue, "| chars:", candidate.count, "| req:", self.speculativeRequestsThisSession)
        }

        speculativeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + SpeculativeConfig.debounce, execute: workItem)
    }

    private func fetchPolishedDraft(
        text: String,
        mode: DraftMode,
        ctx: FieldContext?,
        targetLanguageOverride: String?
    ) async throws -> PolishResponse {
        speculativeDebounceWorkItem?.cancel()
        speculativeDebounceWorkItem = nil
        let effectiveTargetLanguage = effectiveTargetLanguage(overrideCode: targetLanguageOverride)
        if let speculative = speculativeDraft,
           speculative.text == text,
           speculative.mode == mode,
           speculative.targetLanguage.caseInsensitiveCompare(effectiveTargetLanguage) == .orderedSame {
            speculativeDraft = nil
            do {
                print("⚡️ reuse speculative result")
                return try await speculative.task.value
            } catch AIClientError.cancelled {
                // Fall back to normal request.
            } catch {
                print("⚠️ speculative failed, retry live:", error.localizedDescription)
            }
        } else if let speculative = speculativeDraft {
            speculative.task.cancel()
            speculativeDraft = nil
        }

        return try await ai.draft(
            text: text,
            mode: mode,
            ctx: ctx,
            targetLanguageOverride: effectiveTargetLanguage
        )
    }

    private func shouldAcceptAIOutput(_ text: String, targetLanguage: String) -> Bool {
        let target = targetLanguage.lowercased()
        guard target.hasPrefix("nb") || target.hasPrefix("nn") || target.hasPrefix("no") else {
            if target.hasPrefix("en") {
                let lower = text.lowercased()
                if lower.range(of: #"\[[^\]]{1,32}\]"#, options: .regularExpression) != nil {
                    return false
                }
                let hasNorwegianWords = lower.contains("hei ")
                    || lower.contains(" hilsen")
                    || lower.contains("vennlig")
                    || lower.contains("med vennlig")
                let hiCount = lineStartsCount(in: text, prefixes: LanguageGuard.englishGreetingPrefixes)
                let signoffCount = lineStartsCount(in: text, prefixes: LanguageGuard.englishSignoffPrefixes)
                if hasNorwegianWords { return false }
                if hiCount > 1 || signoffCount > 1 { return false }
            }
            return true
        }

        let lower = text.lowercased()
        if lower.range(of: #"[ąćęłńóśźż]"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private func shouldForceEmailReplace(immediate: String, polished: String, mode: DraftMode) -> Bool {
        guard mode == .emailBody else { return false }

        let immediateTrim = immediate.trimmingCharacters(in: .whitespacesAndNewlines)
        let polishedTrim = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !immediateTrim.isEmpty, !polishedTrim.isEmpty, immediateTrim != polishedTrim else { return false }

        let correctionCuePattern = #"\b(nei|no)\b"#
        let immediateHasCorrectionCue = immediateTrim.range(
            of: correctionCuePattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let polishedHasCorrectionCue = polishedTrim.range(
            of: correctionCuePattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if immediateHasCorrectionCue && !polishedHasCorrectionCue {
            return true
        }

        // If polished has a sign-off + name but immediate does not, always replace.
        let signoffWithNamePattern = #"(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s*,?\s*\n\s*[^\n]{2,}$"#
        let polishedHasSignoffName = polishedTrim.range(of: signoffWithNamePattern, options: [.regularExpression, .caseInsensitive]) != nil
        let immediateHasSignoffName = immediateTrim.range(of: signoffWithNamePattern, options: [.regularExpression, .caseInsensitive]) != nil
        if polishedHasSignoffName && !immediateHasSignoffName {
            return true
        }

        let looseSignoffTailPattern = #"\s(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s*[.!?]?\s*$"#
        let immediateHasLooseSignoffTail = immediateTrim.range(
            of: looseSignoffTailPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let polishedHasStructuredSignoff = polishedTrim.range(
            of: #"\n\n(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s*,?(?:\n|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if immediateHasLooseSignoffTail && polishedHasStructuredSignoff {
            return true
        }

        return false
    }

    private func lineStartsCount(in text: String, prefixes: [String]) -> Int {
        text.split(separator: "\n").reduce(0) { partial, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matched = prefixes.contains { trimmed.hasPrefix($0) }
            return partial + (matched ? 1 : 0)
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func logDictation(text: String, mode: DictationMode, appName: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if Thread.isMainThread {
            DictationHistory.shared.add(text: trimmed, mode: mode, appName: appName)
        } else {
            DispatchQueue.main.async {
                DictationHistory.shared.add(text: trimmed, mode: mode, appName: appName)
            }
        }
    }

    private func resetSpeculativeState(cancel: Bool) {
        if cancel {
            speculativeDraft?.task.cancel()
        }
        speculativeDebounceWorkItem?.cancel()
        speculativeDebounceWorkItem = nil
        speculativeDraft = nil
        lastSpeculativeText = ""
        lastSpeculativeStartedAt = .distantPast
        speculativeRequestsThisSession = 0
    }

    private func consumeOneShotOutputLanguageOverride() -> String? {
        let override = oneShotOutputLanguageOverride
        oneShotOutputLanguageOverride = nil
        return override
    }

    private func clearOneShotOutputLanguageOverride() {
        oneShotOutputLanguageOverride = nil
    }

    private func effectiveTargetLanguage(overrideCode: String?) -> String {
        let chosen = (overrideCode ?? ai.targetLanguage).trimmingCharacters(in: .whitespacesAndNewlines)
        return chosen.isEmpty ? SpeechConfig.fallbackLocale : chosen
    }

    private func localPolish(text: String, mode: DraftMode) -> String {
        let corrected = applyingLocalSelfCorrections(text, interpretationLevel: interpretationLevel)
        if interpretationLevel == .literal {
            return corrected
        }
        switch mode {
        case .emailSubject:
            return corrected.replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
        case .emailBody:
            return normalizeEmailBody(corrected)
        default:
            return applyImplicitListFormattingIfNeeded(corrected)
        }
    }

    private func applyingLocalSelfCorrections(
        _ text: String,
        interpretationLevel: InterpretationLevel
    ) -> String {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        if out.isEmpty { return out }

        if interpretationLevel != .literal {
            for _ in 0..<3 {
                let previous = out
                out = replacingMatches(in: out, using: LocalPolishRegex.inlineTimeCorrection, with: "$2")
                out = replacingMatches(in: out, using: LocalPolishRegex.inlineHourCorrection, with: "$2")
                out = replacingMatches(in: out, using: LocalPolishRegex.inlineAmountCorrection, with: "$2")
                if out == previous { break }
            }
            out = replacingMatches(in: out, using: LocalPolishRegex.fillerWords, with: "$1")
        }
        out = applySpokenPunctuationAliases(out)
        out = replacingMatches(in: out, using: EmailBodyRegex.spaceBeforePunctuation, with: "$1")
        out = replacingMatches(in: out, using: EmailBodyRegex.trailingWhitespace, with: "")
        out = replacingMatches(in: out, using: EmailBodyRegex.extraNewlines, with: "\n\n")

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applySpokenPunctuationAliases(_ text: String) -> String {
        var out = text
        if out.isEmpty { return out }

        let aliases: [(pattern: String, mark: String)] = [
            (#"\b(?:skråstrek|skraastrek|slash|slahs|slashtegn)\b"#, "/"),
            (#"\b(?:backslash|bakoverstrek)\b"#, "\\"),
            (#"\b(?:komma|comma)\b"#, ","),
            (#"\b(?:punktum|period|full\s*stop)\b"#, "."),
            (#"\b(?:kolon|colon)\b"#, ":"),
            (#"\b(?:semikolon|semicolon)\b"#, ";"),
            (#"\b(?:utropstegn|exclamation\s*(?:mark|point))\b"#, "!"),
            (#"\b(?:spørsmålstegn|sporsmalstegn|question\s*mark)\b"#, "?"),
            (#"\b(?:apostrof|apostrophe)\b"#, "'"),
            (#"\b(?:anførselstegn|anforselstegn|sitattegn|quotation\s*mark|quote)\b"#, "\""),
            (#"\b(?:bindestrek|hyphen)\b"#, "-"),
            (#"\b(?:dash|en\s*dash|em\s*dash)\b"#, " – "),
            (#"\b(?:ellipse|ellipsis|tre\s+prikker|three\s+dots)\b"#, "…"),
            (#"\b(?:åpen|open)\s+(?:square\s+)?bracket\b"#, "["),
            (#"\b(?:lukk|close)\s+(?:square\s+)?bracket\b"#, "]"),
            (#"\b(?:åpen|open)\s+(?:curly\s+)?brace\b"#, "{"),
            (#"\b(?:lukk|close)\s+(?:curly\s+)?brace\b"#, "}")
        ]

        for alias in aliases {
            out = out.replacingOccurrences(
                of: alias.pattern,
                with: alias.mark,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        out = out.replacingOccurrences(
            of: #"([\p{L}\p{N}])\s*/\s*([\p{L}\p{N}])"#,
            with: "$1/$2",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"\b(?:åpen|open|start|venstre|left)\s+(?:parentes|parenthesis)\b"#,
            with: "(",
            options: [.regularExpression, .caseInsensitive]
        )
        out = out.replacingOccurrences(
            of: #"\b(?:lukk|slutt|close|høyre|right)\s+(?:parentes|parenthesis)\b"#,
            with: ")",
            options: [.regularExpression, .caseInsensitive]
        )
        out = out.replacingOccurrences(
            of: #"[ \t]+([,.;:!?])"#,
            with: "$1",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"([,.;:!?])([^\s\n)\]}])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"\(\s+"#,
            with: "(",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"\s+\)"#,
            with: ")",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return out
    }

    private func applyImplicitListFormattingIfNeeded(_ text: String) -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty { return source }
        if source.range(of: #"^\s*[-•*]\s+"#, options: .regularExpression) != nil { return source }
        if source.range(of: #"\b(?:trenger|må\s+ha|skal\s+ha|må\s+kjøpe|kjøp|hand(?:le)?list(?:e|en|a)|shopping\s*list|shoppinglist|grocery\s*list|ingredienser|for\s+dinner|til\s+middag|we\s+need|need|buy|get)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            return source
        }

        let stripped = stripListLeadPhrasesLocal(source)
        let rawItems = splitListItemsLocal(stripped)
        if rawItems.isEmpty { return source }

        var finalItems: [String] = []
        var indexByKey: [String: Int] = [:]

        for raw in rawItems {
            let normalized = normalizeListItemLocal(raw)
            if normalized.isEmpty { continue }

            if let negated = extractNegatedListItemLocal(from: normalized) {
                if let idx = indexByKey[negated] {
                    finalItems[idx] = ""
                    indexByKey.removeValue(forKey: negated)
                }
                continue
            }

            let key = normalized
            if indexByKey[key] != nil { continue }
            indexByKey[key] = finalItems.count
            finalItems.append(normalized)
        }

        let items = finalItems
            .filter { !$0.isEmpty && isLikelySimpleListItemLocal($0) && !isListContextOnlyItemLocal($0) }
        if items.count < 2 { return source }

        let listBody = items.map { "- \($0)" }.joined(separator: "\n")
        let heading = applyListTimingQualifierLocal(
            inferLocalListHeading(from: source, output: listBody),
            source: source,
            output: listBody
        )
        let body = items.map { "- \($0)" }.joined(separator: "\n")
        if let heading, !heading.isEmpty {
            return "\(heading)\n\(body)"
        }
        return body
    }

    private func inferLocalListHeading(from source: String, output: String) -> String? {
        let lower = source.lowercased()
        let outputLower = output.lowercased()
        let englishSignal = outputLower.range(of: #"\b(?:for|tomorrow|shopping|ingredients|we need|milk|eggs|bread)\b"#, options: .regularExpression) != nil

        if lower.range(of: #"\bfor\s+dinner\b"#, options: .regularExpression) != nil {
            return "What we need for dinner:"
        }
        if lower.range(of: #"\btil\s+middag\b"#, options: .regularExpression) != nil {
            return "Det vi trenger til middag:"
        }
        if lower.range(of: #"\b(?:shopping\s*list|shoppinglist|grocery\s*list|on\s+my\s+shopping\s+list)\b"#, options: .regularExpression) != nil {
            return "Shopping list"
        }
        if lower.range(of: #"\b(?:hand(?:le)?list(?:e|en|a)|innkjøpsliste)\b"#, options: .regularExpression) != nil {
            return englishSignal ? "Shopping list" : "Handleliste"
        }
        return nil
    }

    private func applyListTimingQualifierLocal(_ heading: String?, source: String, output: String) -> String? {
        guard var heading, !heading.isEmpty else { return heading }
        let combined = "\(source)\n\(output)".lowercased()

        let hasTomorrow = combined.range(of: #"\b(?:for\s+tomorrow|tomorrow|i\s+morgen|til\s+i\s+morgen)\b"#, options: .regularExpression) != nil
        let hasToday = combined.range(of: #"\b(?:for\s+today|today|i\s+dag|til\s+i\s+dag)\b"#, options: .regularExpression) != nil
        let hasTonight = combined.range(of: #"\b(?:for\s+tonight|tonight|i\s+kveld|til\s+i\s+kveld)\b"#, options: .regularExpression) != nil
        if !hasTomorrow && !hasToday && !hasTonight { return heading }

        let englishHeading = heading.lowercased().contains("shopping") || heading.lowercased().contains("what we need")
        let qualifier: String
        if hasTomorrow {
            qualifier = englishHeading ? "for tomorrow" : "til i morgen"
        } else if hasToday {
            qualifier = englishHeading ? "for today" : "for i dag"
        } else {
            qualifier = englishHeading ? "for tonight" : "for i kveld"
        }

        if heading.lowercased().contains(qualifier.lowercased()) { return heading }
        if heading.hasSuffix(":") {
            heading.removeLast()
            return "\(heading) \(qualifier):"
        }
        return "\(heading) \(qualifier):"
    }

    private func stripListLeadPhrasesLocal(_ text: String) -> String {
        var out = text
        let replacements: [(pattern: String, replace: String)] = [
            (#"^\s*(?:shopping\s*list|shoppinglist|grocery\s*list|hand(?:le)?list(?:e|en|a)|innkjøpsliste)\s*[:\-]\s*(?:i\s+want|jeg\s+ønsker|jeg\s+vil\s+ha|vi\s+trenger|we\s+need)\s+[^,\n;]+(?:\s*[,;]\s*|$)"#, ""),
            (#"^\s*(?:(?:jeg|vi)\s+skal\s+ha\s+(?:en|ei|et)?\s+)?(?:shopping\s*list|shoppinglist|grocery\s*list|hand(?:le)?list(?:e|en|a)|innkjøpsliste)\s*(?:[:,]|\s+med)?\s*"#, ""),
            (#"^\s*(?:on\s+my\s+shopping\s+list|på\s+hand(?:le)?list(?:e|en|a))\s*[:,]?\s*"#, ""),
            (#"^\s*(?:(?:jeg|vi)\s+skal\s+ha\s+(?:en|ei|et)?\s+)?(?:til\s+[^\s,.;:!?]+(?:\s+[^\s,.;:!?]+){0,2}\s+)?(?:trenger\s+vi|vi\s+trenger|we\s+need|need|kjøp|buy|get|hand(?:le)?liste(?:n)?|ingredienser(?:\s+til\s+[^\s,.;:!?]+)?)\s*(?:med\s+)?"#, ""),
            (#"^\s*med\s+"#, "")
        ]

        for replacement in replacements {
            out = out.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.replace,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        out = out.replacingOccurrences(
            of: #"\b(?:vi\s+trenger|trenger\s+vi|we\s+need|need)\b"#,
            with: ", ",
            options: [.regularExpression, .caseInsensitive]
        )
        out = out.replacingOccurrences(
            of: #"\b(?:i\s+want|jeg\s+vil\s+ha|jeg\s+trenger)\b"#,
            with: ", ",
            options: [.regularExpression, .caseInsensitive]
        )

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitListItemsLocal(_ content: String) -> [String] {
        var working = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if working.isEmpty { return [] }

        working = working.replacingOccurrences(
            of: #"\b(?:punkt|point)\s*(?:\d+|en|ett|to|tre|fire|fem|seks|sju|syv|åtte|ni|ti|one|two|three|four|five|six|seven|eight|nine|ten)\s*[:.)-]?\s*"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        working = working.replacingOccurrences(
            of: #"\s*\n+\s*"#,
            with: "\n",
            options: .regularExpression
        )

        var parts: [String]
        if working.contains("\n") {
            parts = working.components(separatedBy: CharacterSet.newlines)
        } else if working.range(of: #"[;,]"#, options: .regularExpression) != nil {
            parts = working.components(separatedBy: CharacterSet(charactersIn: ";,"))
        } else if working.range(of: #"\b(?:og|and)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let markerSplit = working.replacingOccurrences(
                of: #"\s+\b(?:og|and)\b\s+"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            parts = markerSplit.components(separatedBy: CharacterSet.newlines)
        } else {
            parts = [working]
        }

        var expanded: [String] = []
        for part in parts {
            let segment = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if segment.isEmpty { continue }
            let splitAndRaw = segment.replacingOccurrences(
                of: #"\s+\b(?:og|and)\b\s+"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            let splitAnd = splitAndRaw.components(separatedBy: CharacterSet.newlines)
            if splitAnd.count > 1 {
                for item in splitAnd where !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    expanded.append(item)
                }
            } else {
                expanded.append(segment)
            }
        }

        return expanded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func normalizeListItemLocal(_ value: String) -> String {
        var token = value
            .lowercased()
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return "" }

        let replacements: [String] = [
            #"^[\-•*]\s*"#,
            #"^(?:og|and)\s+"#,
            #"^(?:(?:jeg|vi)\s+skal\s+ha\s+(?:en|ei|et)?\s+)?(?:shopping\s*list|shoppinglist|grocery\s*list|hand(?:le)?list(?:e|en|a)|innkjøpsliste)\s*(?:[:\-]|\s+med)?\s*"#,
            #"^(?:on\s+my\s+shopping\s+list|på\s+hand(?:le)?list(?:e|en|a))\s*[:,]?\s*"#,
            #"^(?:i\s+want|jeg\s+vil\s+ha|jeg\s+trenger)\s+"#,
            #"^(?:til\s+[a-zæøå][a-zæøå\-']{1,24})\s+(?:trenger|må\s+ha|need|we\s+need)\s+"#,
            #"^(?:(?:jeg|vi)\s+)?(?:trenger|må\s+ha|skal\s+ha|må\s+kjøpe|kjøp|need|we\s+need|buy|get)\s+"#,
            #"^med\s+"#
        ]

        for pattern in replacements {
            token = token.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        token = token.replacingOccurrences(
            of: #"[.,;:!?]+$"#,
            with: "",
            options: .regularExpression
        )

        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractNegatedListItemLocal(from value: String) -> String? {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"^(?:men\s+)?(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+)?\s*(?:(?:nei|no)\s+(?:(?:ikke|not)\s+)?)?(.+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = regex.firstMatch(in: token, options: [], range: range),
              let capturedRange = Range(match.range(at: 1), in: token) else {
            return nil
        }

        let hasNegationCue = token.range(
            of: #"^(?:men\s+)?(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+)?\s*(?:nei|no)\b|^(?:ikke|not|uten|without)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if !hasNegationCue { return nil }

        let candidate = normalizeListItemLocal(String(token[capturedRange]))
        return candidate.isEmpty ? nil : candidate
    }

    private func isLikelySimpleListItemLocal(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return false }

        let words = value.split(whereSeparator: \.isWhitespace)
        if words.count < 1 || words.count > 4 { return false }
        if value.range(of: #"^(?:å|to|ellers|if|hvis|fordi)\b"#, options: .regularExpression) != nil { return false }
        if value.range(of: #"^(?:jeg|vi|du|dere|han|hun|de|it|we|you|they)\b"#, options: .regularExpression) != nil { return false }
        if value.range(of: #"\b(?:er|blir|ble|skal|må|kan|kunne|vil|ville|har|hadde|får|fikk|is|are|was|were|be|being|have|has|had|will|would|should|could)\b"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private func isListContextOnlyItemLocal(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return false }
        return value.range(
            of: #"^(?:for\s+(?:today|tomorrow|tonight)|today|tomorrow|tonight|i\s+dag|i\s+morgen|i\s+kveld|til\s+i\s+dag|til\s+i\s+morgen|til\s+i\s+kveld|for\s+i\s+dag|for\s+i\s+morgen|for\s+i\s+kveld)$"#,
            options: .regularExpression
        ) != nil
    }

    private func normalizeEmailBody(_ text: String) -> String {
        var out = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return out }

        out = replacingMatches(in: out, using: EmailBodyRegex.greeting, with: "$1 $2,\n\n")
        out = replacingMatches(in: out, using: EmailBodyRegex.splitSignoffEN, with: "$1 $2")
        out = replacingMatches(in: out, using: EmailBodyRegex.splitSignoffNO, with: "$1 $2")
        out = replacingMatches(in: out, using: EmailBodyRegex.inlineSignoff, with: "\n\n$1 ")
        out = replacingMatches(in: out, using: EmailBodyRegex.inlineSignoffAtEnd, with: "\n\n$1,")
        out = replacingMatches(in: out, using: EmailBodyRegex.signoffAtEnd, with: "\n\n$1,\n$2")
        out = replacingMatches(in: out, using: EmailBodyRegex.signoffNoNameAtEnd, with: "\n\n$1,")
        out = replacingMatches(in: out, using: EmailBodyRegex.greetingMissingParagraph, with: "$0\n")
        out = replacingMatches(in: out, using: EmailBodyRegex.spaceBeforePunctuation, with: "$1")
        out = replacingMatches(in: out, using: EmailBodyRegex.punctuationJoin, with: "$1 $2")
        out = replacingMatches(in: out, using: EmailBodyRegex.trailingWhitespace, with: "")
        out = replacingMatches(in: out, using: EmailBodyRegex.extraNewlines, with: "\n\n")
        out = replacingMatches(in: out, using: EmailBodyRegex.signoffNormalized, with: "\n\n$1,\n$2")
        out = normalizeEmailLineCasingAndPunctuation(out)

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeEmailLineCasingAndPunctuation(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var outLines: [String] = []
        outLines.reserveCapacity(lines.count)

        var previousLineWasSignoff = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                outLines.append("")
                previousLineWasSignoff = false
                continue
            }

            if let normalizedGreeting = normalizedGreetingLine(trimmed) {
                outLines.append(normalizedGreeting)
                previousLineWasSignoff = false
                continue
            }

            if let canonicalSignoff = canonicalSignoffLine(trimmed) {
                outLines.append(canonicalSignoff)
                previousLineWasSignoff = true
                continue
            }

            if previousLineWasSignoff && isLikelyNameLine(trimmed) {
                let cleanedName = trimmed.replacingOccurrences(
                    of: #"[,.;:!?]+$"#,
                    with: "",
                    options: .regularExpression
                )
                outLines.append(capitalizeFirstLetter(cleanedName))
                previousLineWasSignoff = false
                continue
            }

            var normalized = capitalizeFirstLetter(trimmed)
            if !hasTerminalPunctuation(normalized) && isLikelyQuestionLine(normalized) {
                normalized += "?"
            }

            outLines.append(normalized)
            previousLineWasSignoff = false
        }

        return outLines.joined(separator: "\n")
    }

    private func canonicalSignoffLine(_ line: String) -> String? {
        let key = line
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[,.;:!?]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch key {
        case "med vennlig hilsen":
            return "Med vennlig hilsen,"
        case "vennlig hilsen":
            return "Vennlig hilsen,"
        case "hilsen":
            return "Hilsen,"
        case "mvh":
            return "Mvh,"
        case "best regards":
            return "Best regards,"
        case "regards":
            return "Regards,"
        case "best":
            return "Best,"
        case "sincerely":
            return "Sincerely,"
        default:
            return nil
        }
    }

    private func normalizedGreetingLine(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(Hei|Hi|Hello|Dear)\s+([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå'\-]*(?:\s+[A-Za-zÆØÅæøå][A-Za-zÆØÅæøå'\-]*){0,3}),?$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let greetingRange = Range(match.range(at: 1), in: line),
              let nameRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let greeting = capitalizeFirstLetter(line[greetingRange].lowercased())
        let normalizedName = titleCaseWords(String(line[nameRange]))
        return "\(greeting) \(normalizedName),"
    }

    private func isLikelyQuestionLine(_ line: String) -> Bool {
        line.range(
            of: #"^(skal|kan|kunne|vil|har|hva|hvordan|hvor|hvem|hvilken|hvilke|when|what|why|how|can|could|would|will|do|did|are|is|should)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func isLikelyNameLine(_ line: String) -> Bool {
        line.range(
            of: #"^[A-Za-zÆØÅæøå][A-Za-zÆØÅæøå'\- ]{0,40}$"#,
            options: .regularExpression
        ) != nil
    }

    private func hasTerminalPunctuation(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        return ".!?".contains(last)
    }

    private func capitalizeFirstLetter(_ line: String) -> String {
        guard let first = line.first, first.isLowercase else { return line }
        return String(first).uppercased() + line.dropFirst()
    }

    private func titleCaseWords(_ text: String) -> String {
        text
            .split(separator: " ")
            .map { token in
                guard let first = token.first else { return String(token) }
                let rest = token.dropFirst().lowercased()
                return String(first).uppercased() + rest
            }
            .joined(separator: " ")
    }

    private func replacingMatches(in text: String, using regex: NSRegularExpression?, with template: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private func replaceLastInserted(
        raw: String,
        polished: String,
        initialInsertMode: InsertionMode,
        finalInsertMode: InsertionMode
    ) {
        guard !raw.isEmpty else { return }

        // ContentEditable (Gmail/Outlook) can insert hidden trailing chars on paste.
        // Undo is more reliable than character-count selection for replacing last paste.
        if initialInsertMode == .pasteOnly || initialInsertMode == .hybrid {
            sendCmdZ()
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.replaceDelay) {
                self.insertText(polished, insertMode: finalInsertMode, completion: nil)
            }
            return
        }

        selectBackward(count: raw.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.replaceDelay) {
            self.insertText(polished, insertMode: finalInsertMode, completion: nil)
        }
    }

    private func selectBackward(count: Int) {
        guard count > 0 else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let leftArrow: CGKeyCode = 123

        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: src, virtualKey: leftArrow, keyDown: true)
            down?.flags = .maskShift
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: src, virtualKey: leftArrow, keyDown: false)
            up?.flags = .maskShift
            up?.post(tap: .cghidEventTap)
        }
    }

    // Setter både plain text + HTML i clipboard, så Gmail kan beholde linjeskift/struktur.
    private func insertViaPaste(_ text: String, completion: (() -> Void)?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if let htmlData = htmlClipboardData(from: text) {
            pb.setData(htmlData, forType: .html)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pasteDelay) {
            self.sendCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pasteCompletionDelay) {
                completion?()
            }
        }
    }

    private func htmlClipboardData(from text: String) -> Data? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let htmlBody = htmlEscapedClipboardFragment(from: normalized)
        let html = "<meta charset=\"utf-8\"><!--StartFragment--><span style=\"white-space:pre-wrap;\">\(htmlBody)</span><!--EndFragment-->"
        return html.data(using: .utf8)
    }

    private func htmlEscapedClipboardFragment(from text: String) -> String {
        var out = String()
        out.reserveCapacity(text.utf16.count * 3)

        for scalar in text.unicodeScalars {
            switch scalar {
            case "&":
                out += "&amp;"
            case "<":
                out += "&lt;"
            case ">":
                out += "&gt;"
            case "\"":
                out += "&quot;"
            case "'":
                out += "&#39;"
            case "\n":
                out += "<br>"
            default:
                if scalar.value <= 0x7F {
                    out.unicodeScalars.append(scalar)
                } else {
                    out += "&#\(scalar.value);"
                }
            }
        }

        return out
    }

    private func sendEnter() {
        postKeyPress(36)
    }

    private func sendCmdV() {
        postKeyPress(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    private func sendCmdZ() {
        postKeyPress(CGKeyCode(kVK_ANSI_Z), flags: .maskCommand)
    }

    private func sendTab() {
        postKeyPress(48)
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

    private func typeText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            if scalar.value == 10 || scalar.value == 13 {
                sendEnter()
                continue
            }
            if scalar.value == 9 {
                sendTab()
                continue
            }

            var u = UInt16(scalar.value)

            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
            up?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Speech

    private func playStartSound() {
        guard let startSound else {
            NSSound.beep()
            return
        }
        startSound.stop()
        startSound.currentTime = 0
        startSound.volume = SpeechConfig.startSoundVolume
        if !startSound.play() {
            NSSound.beep()
        }
    }

    private func startGroqInternal(startToken: Int) {
        guard shouldProceedStart(token: startToken) else { return }
        guard !isRecording else { return }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil

        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir
            .appendingPathComponent("bluespeak-stt-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let m4aURL = tempDir
            .appendingPathComponent("bluespeak-stt-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: GroqConfig.sampleRateWav,
            AVNumberOfChannelsKey: GroqConfig.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let aacSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: GroqConfig.sampleRateAAC,
            AVNumberOfChannelsKey: GroqConfig.channelCount,
            AVEncoderBitRateKey: GroqConfig.aacBitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let attempts: [(url: URL, settings: [String: Any], format: String)] = [
            (wavURL, wavSettings, "wav_pcm_16k"),
            (m4aURL, aacSettings, "m4a_aac_44k")
        ]

        for attempt in attempts {
            do {
                let recorder = try AVAudioRecorder(url: attempt.url, settings: attempt.settings)
                recorder.prepareToRecord()
                if recorder.record() {
                    groqRecorder = recorder
                    groqRecordingURL = attempt.url

                    print(
                        "🎤 groq stt locale:",
                        speechLocaleIdentifier,
                        "| ai target:",
                        effectiveTargetLanguage(overrideCode: oneShotOutputLanguageOverride),
                        "| mic:",
                        selectedMicrophoneNameForLogs(),
                        "| format:",
                        attempt.format
                    )
                    playStartSound()

                    isStarting = false
                    isRecording = true
                    captureStartedAt = Date()
                    return
                }

                AppLogStore.shared.record(
                    .warning,
                    "Groq recorder start returned false",
                    metadata: [
                        "format": attempt.format,
                        "path": attempt.url.path
                    ]
                )
            } catch {
                AppLogStore.shared.record(
                    .warning,
                    "Groq recorder setup failed",
                    metadata: [
                        "format": attempt.format,
                        "error": error.localizedDescription
                    ]
                )
            }
        }

        reportCaptureInterruption("Could not start microphone capture.")
        cancelPendingStart()
    }

    private func transcribeGroqAudioFile(_ fileURL: URL) async throws -> String {
        let apiKey = settings.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AIClientError.transport("Missing Groq API key.")
        }

        let languageHint = normalizedGroqLanguageHint(from: speechLocaleIdentifier)
        let boundary = "----BlueSpeakSTT\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: GroqConfig.endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = GroqConfig.timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data = try Data(contentsOf: fileURL)
        let payload = multipartPayload(
            boundary: boundary,
            audioData: data,
            audioFileURL: fileURL,
            languageHint: languageHint
        )
        request.httpBody = payload

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = GroqConfig.timeout
        sessionConfig.timeoutIntervalForResource = GroqConfig.timeout + 2
        let session = URLSession(configuration: sessionConfig)
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.transport("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw AIClientError.badStatus(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(GroqTranscriptionResponse.self, from: responseData)
        let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private func multipartPayload(
        boundary: String,
        audioData: Data,
        audioFileURL: URL,
        languageHint: String?
    ) -> Data {
        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", value: GroqConfig.model)
        appendField("temperature", value: "0")
        appendField("response_format", value: "verbose_json")
        if let languageHint, !languageHint.isEmpty {
            appendField("language", value: languageHint)
        }

        let fileName = audioFileURL.lastPathComponent
        let mimeType = mimeTypeForAudioFile(audioFileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func mimeTypeForAudioFile(_ fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        default:
            return "application/octet-stream"
        }
    }

    private func normalizedGroqLanguageHint(from locale: String) -> String {
        let lower = locale.lowercased()
        if lower.hasPrefix("nb") || lower.hasPrefix("nn") || lower.hasPrefix("no") {
            return "no"
        }
        if lower.hasPrefix("en") {
            return "en"
        }
        if lower.hasPrefix("es") {
            return "es"
        }
        if lower.hasPrefix("fr") {
            return "fr"
        }
        if lower.hasPrefix("de") {
            return "de"
        }
        if lower.hasPrefix("pt") {
            return "pt"
        }
        if lower.hasPrefix("it") {
            return "it"
        }
        if lower.hasPrefix("nl") {
            return "nl"
        }
        if lower.hasPrefix("pl") {
            return "pl"
        }
        if lower.hasPrefix("ar") {
            return "ar"
        }
        if lower.hasPrefix("uk") {
            return "uk"
        }
        return "en"
    }

    private func startInternal(startToken: Int) {
        guard shouldProceedStart(token: startToken) else { return }
        guard !isRecording else { return }
        let locale = Locale(identifier: speechLocaleIdentifier)
        let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: SpeechConfig.fallbackLocale))
        guard let recognizer, recognizer.isAvailable else {
            reportCaptureInterruption("Speech recognition is temporarily unavailable.")
            cancelPendingStart()
            return
        }
        let selectedMicrophone = applyPreferredInputDeviceIfNeeded()
        print(
            "🎤 speech locale:",
            speechLocaleIdentifier,
            "| ai target:",
            effectiveTargetLanguage(overrideCode: oneShotOutputLanguageOverride),
            "| mic:",
            selectedMicrophone
        )
        playStartSound()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: SpeechConfig.audioBufferSize, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            reportCaptureInterruption("Failed to start microphone: \(error.localizedDescription)")
            stopInternal()
            return
        }

        isStarting = false
        isRecording = true
        captureStartedAt = Date()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let partial = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.finalText = partial
                    self.hasReceivedTranscriptInCurrentCapture = true
                    self.onPartial?(partial)
                    self.maybeStartSpeculativeDraft(with: partial)
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    let shouldNotify = self.isRecording || self.isStarting
                    self.stopInternal()
                    self.resetSpeculativeState(cancel: true)
                    self.finalText = ""
                    self.hasReceivedTranscriptInCurrentCapture = false
                    if shouldNotify {
                        self.reportCaptureInterruption(error?.localizedDescription)
                    }
                }
            }
        }
    }

    private func consumeCapturedTranscript() -> String {
        defer {
            finalText = ""
            hasReceivedTranscriptInCurrentCapture = false
        }
        guard hasReceivedTranscriptInCurrentCapture else { return "" }
        return polishBasic(finalText)
    }

    private func stopInternal() {
        expectedStartToken = 0
        isStarting = false
        isRecording = false
        clearOneShotOutputLanguageOverride()

        if let recorder = groqRecorder {
            if recorder.isRecording {
                recorder.stop()
            }
            groqRecorder = nil
        }

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        request?.endAudio()

        task?.cancel()
        task = nil
        request = nil
    }

    private func applyPreferredInputDeviceIfNeeded() -> String {
        let selectedUID = settings.selectedMicrophoneUID
        if selectedUID == MicrophoneOption.systemDefaultID {
            return "System Default"
        }

        guard let deviceID = audioDeviceID(forUID: selectedUID) else {
            print("⚠️ selected microphone unavailable, fallback to system default")
            settings.selectedMicrophoneUID = MicrophoneOption.systemDefaultID
            return "System Default"
        }

        guard let audioUnit = audioEngine.inputNode.audioUnit else {
            print("⚠️ input audio unit unavailable, using system default")
            return "System Default"
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            print("⚠️ failed to set microphone (\(status)), using system default")
            return "System Default"
        }

        return MicrophoneCatalog.availableOptions()
            .first(where: { $0.id == selectedUID })?
            .name ?? selectedUID
    }

    private func selectedMicrophoneNameForLogs() -> String {
        let selectedUID = settings.selectedMicrophoneUID
        if selectedUID == MicrophoneOption.systemDefaultID {
            return "System Default"
        }
        return MicrophoneCatalog.availableOptions()
            .first(where: { $0.id == selectedUID })?
            .name ?? selectedUID
    }

    private func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return nil }

        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return nil
        }

        for deviceID in deviceIDs where isInputDevice(deviceID) {
            if deviceUID(for: deviceID) == uid {
                return deviceID
            }
        }

        return nil
    }

    private func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }

        guard dataSize > 0 else { return false }
        var storage = Data(count: Int(dataSize))
        let readStatus: OSStatus = storage.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, baseAddress)
        }
        guard readStatus == noErr else {
            return false
        }

        let channelCount: Int = storage.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return 0 }
            let listPointer = baseAddress.assumingMemoryBound(to: AudioBufferList.self)
            let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
            return buffers.reduce(0) { partial, buffer in
                partial + Int(buffer.mNumberChannels)
            }
        }
        return channelCount > 0
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var cfUID: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr, let cfUID else { return nil }

        return cfUID as String
    }

    private func shouldProceedStart(token: Int) -> Bool {
        token != 0 && token == expectedStartToken && isStarting && !isRecording
    }

    private func cancelPendingStart() {
        stopInternal()
    }

    private func reportCaptureInterruption(_ message: String?) {
        markCaptureFailure(for: activeSTTProvider, message: message)
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLogStore.shared.record(.warning, "Capture interrupted", metadata: ["message": message])
        }
        DispatchQueue.main.async {
            self.onCaptureInterrupted?(message)
        }
    }

    private func markCaptureSuccess(for provider: STTProvider) {
        guard captureMode == .dictation, settings.sttProvider == .appleSpeech else { return }
        guard provider == .appleSpeech else { return }
        if appleConsecutiveFailures > 0 || autoFallbackCapturesRemaining > 0 {
            AppLogStore.shared.record(
                .info,
                "Apple STT recovered",
                metadata: [
                    "failureStreakBeforeReset": "\(appleConsecutiveFailures)",
                    "fallbackCapturesRemainingBeforeReset": "\(autoFallbackCapturesRemaining)"
                ]
            )
        }
        appleConsecutiveFailures = 0
        autoFallbackCapturesRemaining = 0
    }

    private func markCaptureFailure(for provider: STTProvider, message: String?) {
        guard captureMode == .dictation, settings.sttProvider == .appleSpeech else { return }
        guard provider == .appleSpeech else { return }

        appleConsecutiveFailures += 1
        AppLogStore.shared.record(
            .warning,
            "Apple STT failure",
            metadata: [
                "streak": "\(appleConsecutiveFailures)",
                "message": message ?? "unknown"
            ]
        )

        guard appleConsecutiveFailures >= STTFallbackConfig.appleFailureThreshold else { return }
        let hasGroqKey = !settings.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasGroqKey else {
            AppLogStore.shared.record(
                .warning,
                "STT auto-fallback unavailable",
                metadata: ["reason": "missing_groq_api_key"]
            )
            return
        }

        autoFallbackCapturesRemaining = max(
            autoFallbackCapturesRemaining,
            STTFallbackConfig.fallbackCaptureCount
        )
        AppLogStore.shared.record(
            .warning,
            "STT auto-fallback enabled",
            metadata: [
                "provider": STTProvider.groqWhisperLargeV3.providerLogValue,
                "appleFailureStreak": "\(appleConsecutiveFailures)",
                "fallbackCaptures": "\(autoFallbackCapturesRemaining)"
            ]
        )
    }

    // MARK: - Basic polish

    private func polishBasic(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var s = trimmed
        if let first = s.first, first.isLowercase {
            s.replaceSubrange(s.startIndex...s.startIndex, with: String(first).uppercased())
        }
        if let last = s.last, ".!?".contains(last) == false {
            s += "."
        }
        return s
    }
}

private struct GroqTranscriptionResponse: Decodable {
    let text: String
}

private enum EmailBodyRegex {
    static let greeting = compile(#"^(Hei|Hi|Hello)\s+([^\n,!?]+?)(?:,)?\s+(?=[^\n])"#, options: [.caseInsensitive])
    static let splitSignoffEN = compile(
        #"^(Kind|Best)\s*\n\s*\n?\s*(regards,?)$"#,
        options: [.caseInsensitive, .anchorsMatchLines]
    )
    static let splitSignoffNO = compile(
        #"^(Vennlig|Med vennlig)\s*\n\s*\n?\s*(hilsen,?)$"#,
        options: [.caseInsensitive, .anchorsMatchLines]
    )
    static let inlineSignoff = compile(
        #"\s+(Med vennlig hilsen|Vennlig hilsen|Kind regards|Best regards|Sincerely|Hilsen|Mvh|Regards)\s+"#,
        options: [.caseInsensitive]
    )
    static let inlineSignoffAtEnd = compile(
        #"\s+(Med vennlig hilsen|Vennlig hilsen|Kind regards|Best regards|Sincerely|Hilsen|Mvh|Regards|Best)\s*[.!?]?\s*$"#,
        options: [.caseInsensitive]
    )
    static let signoffAtEnd = compile(
        #"\n\n(Med vennlig hilsen|Vennlig hilsen|Kind regards|Best regards|Sincerely|Hilsen|Mvh|Regards|Best)\s+([^\n]+)$"#,
        options: [.caseInsensitive]
    )
    static let signoffNoNameAtEnd = compile(
        #"\n\n(Med vennlig hilsen|Vennlig hilsen|Kind regards|Best regards|Sincerely|Hilsen|Mvh|Regards|Best)\s*[.!?]?\s*$"#,
        options: [.caseInsensitive]
    )
    static let greetingMissingParagraph = compile(#"^(Hei|Hi|Hello)[^\n]*,\n(?!\n)"#, options: [.caseInsensitive])
    static let spaceBeforePunctuation = compile(#"[ \t]+([,.;!?])"#)
    static let punctuationJoin = compile(#"([,.;!?])([^\s\n])"#)
    static let trailingWhitespace = compile(#"[ \t]+$"#, options: [.anchorsMatchLines])
    static let extraNewlines = compile(#"\n{3,}"#)
    static let signoffNormalized = compile(
        #"\n\n(Med vennlig hilsen|Vennlig hilsen|Kind regards|Best regards|Sincerely|Hilsen|Mvh|Regards|Best)\s*,?\s*\n\s*([^\n]+)$"#,
        options: [.caseInsensitive]
    )

    private static func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }
}

private enum LocalPolishRegex {
    static let inlineTimeCorrection = compile(
        #"(\b(?:kl(?:okken)?\.?\s*)?\d{1,2}[.:]\d{2}\b)\s*(?:[,;.]?\s*)?(?:men\s+)?(?:nei|no)\s*(?:[,;.]?\s*)?(?:jeg mener|i mean)?\s*(?:at\s*)?((?:kl(?:okken)?\.?\s*)?\d{1,2}[.:]\d{2}\b)"#,
        options: [.caseInsensitive]
    )
    static let inlineHourCorrection = compile(
        #"(\b(?:kl(?:okken)?\.?\s*)?\d{1,2}(?:[.:]\d{2})?\b)\s*(?:[,;.]?\s*)?(?:men\s+)?(?:nei|no)\s*(?:[,;.]?\s*)?(?:jeg mener|i mean)?\s*(?:at\s*)?((?:kl(?:okken)?\.?\s*)?\d{1,2}(?:[.:]\d{2})?\b)"#,
        options: [.caseInsensitive]
    )
    static let inlineAmountCorrection = compile(
        #"(\b\d+(?:[.,]\d+)?\s*(?:millioner?|milliarder?|kroner|kr|%)?\b)\s*(?:[,;.]?\s*)?(?:men\s+)?(?:nei|no)\s*(?:[,;.]?\s*)?(?:jeg mener|i mean)?\s*(\d+(?:[.,]\d+)?\s*(?:millioner?|milliarder?|kroner|kr|%)?\b)"#,
        options: [.caseInsensitive]
    )
    static let fillerWords = compile(
        #"(^|[\s,.;:!?()\[\]{}"'`])(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+|erm+|hmm+|mmm+)(?=$|[\s,.;:!?()\[\]{}"'`])"#,
        options: [.caseInsensitive]
    )

    private static func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }
}
