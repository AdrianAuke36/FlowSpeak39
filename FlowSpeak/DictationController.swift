import Foundation
import AVFoundation
import Speech
import AppKit
import Carbon.HIToolbox
import AudioToolbox
import CoreAudio

final class DictationController: NSObject {
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
    private let startSound = NSSound(named: "Pop")

    private(set) var isRecording: Bool = false
    private(set) var isStarting: Bool = false
    var isCaptureActive: Bool { isRecording || isStarting }
    private var finalText: String = ""
    private var startTokenCounter: Int = 0
    private var expectedStartToken: Int = 0

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

    func setStyle(_ style: WritingStyle) {
        ai.style = style
        print("✍️ style:", style.menuLabel)
    }

    func start() {
        guard !isRecording, !isStarting else { return }
        resetSpeculativeState(cancel: true)
        finalText = ""
        startTokenCounter += 1
        let token = startTokenCounter
        expectedStartToken = token
        isStarting = true

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

    func stopAndInsert() {
        if isStarting && !isRecording {
            clearOneShotOutputLanguageOverride()
            cancelPendingStart()
            return
        }
        guard isRecording else { return }
        let outputLanguageOverride = consumeOneShotOutputLanguageOverride()
        stopInternal()
        speculativeDebounceWorkItem?.cancel()
        speculativeDebounceWorkItem = nil

        let raw = polishBasic(finalText)
        guard !raw.isEmpty else {
            resetSpeculativeState(cancel: true)
            return
        }

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
            return ""
        }
        guard isRecording else { return "" }

        stopInternal()
        speculativeDebounceWorkItem?.cancel()
        speculativeDebounceWorkItem = nil

        let captured = polishBasic(finalText)
        resetSpeculativeState(cancel: true)
        return captured
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
        let corrected = applyingLocalSelfCorrections(text)
        switch mode {
        case .emailSubject:
            return corrected.replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
        case .emailBody:
            return normalizeEmailBody(corrected)
        default:
            return corrected
        }
    }

    private func applyingLocalSelfCorrections(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        if out.isEmpty { return out }

        for _ in 0..<3 {
            let previous = out
            out = replacingMatches(in: out, using: LocalPolishRegex.inlineTimeCorrection, with: "$2")
            out = replacingMatches(in: out, using: LocalPolishRegex.inlineHourCorrection, with: "$2")
            out = replacingMatches(in: out, using: LocalPolishRegex.inlineAmountCorrection, with: "$2")
            if out == previous { break }
        }
        out = replacingMatches(in: out, using: LocalPolishRegex.fillerWords, with: "$1")
        out = replacingMatches(in: out, using: EmailBodyRegex.spaceBeforePunctuation, with: "$1")
        out = replacingMatches(in: out, using: EmailBodyRegex.trailingWhitespace, with: "")
        out = replacingMatches(in: out, using: EmailBodyRegex.extraNewlines, with: "\n\n")

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
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

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let partial = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.finalText = partial
                    self.onPartial?(partial)
                    self.maybeStartSpeculativeDraft(with: partial)
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    let shouldNotify = self.isRecording || self.isStarting
                    self.stopInternal()
                    self.resetSpeculativeState(cancel: true)
                    if shouldNotify {
                        self.onCaptureInterrupted?(error?.localizedDescription)
                    }
                }
            }
        }
    }

    private func stopInternal() {
        expectedStartToken = 0
        isStarting = false
        isRecording = false
        clearOneShotOutputLanguageOverride()

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

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
            return false
        }

        let listPointer = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
        let channelCount = buffers.reduce(0) { partial, buffer in
            partial + Int(buffer.mNumberChannels)
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
        DispatchQueue.main.async {
            self.onCaptureInterrupted?(message)
        }
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
