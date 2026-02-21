import Foundation
import AVFoundation
import Speech
import AppKit
import Carbon.HIToolbox

final class DictationController: NSObject {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "nb-NO"))

    private(set) var isRecording: Bool = false
    private var finalText: String = ""

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onInserted: (() -> Void)?

    private let settings = AppSettings.shared

    var aiEnabled: Bool = true
    private let ai = AIClient.shared
    private let resolver = ContextResolver()

    private let pasteDelaySeconds: TimeInterval = 0.08

    func start() {
        finalText = ""

        SFSpeechRecognizer.requestAuthorization { authStatus in
            guard authStatus == .authorized else { return }

            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else { return }
                DispatchQueue.main.async { self.startInternal() }
            }
        }
    }

    func stopAndInsert() {
        guard isRecording else { return }
        stopInternal()

        let raw = polishBasic(finalText)
        guard !raw.isEmpty else { return }

        onFinal?(raw)

        let ctx = resolver.resolve()
        let mode = ctx.map(resolver.draftMode) ?? .generic
        let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let insertMode = settings.mode(for: frontBundleId)

        // OPTIMISTISK INSERT: sett inn rå tekst umiddelbart
        insertText(raw, insertMode: insertMode) { [weak self] in
            self?.onInserted?()
        }

        // Hvis AI er av, er vi ferdige
        guard aiEnabled else { return }

        // AI jobber i bakgrunnen og erstatter teksten når den er klar
        Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.ai.draft(text: raw, mode: mode, ctx: ctx)
                let polished = result.text
                guard polished != raw, !polished.isEmpty else { return }

                DispatchQueue.main.async {
                    self.onFinal?(polished)
                    // Velg ut den råe teksten og erstatt med polert versjon
                    self.replaceLastInserted(raw: raw, polished: polished, insertMode: insertMode)
                }
            } catch {
                // Feil: behold den råe teksten som allerede er satt inn
            }
        }
    }

    // MARK: - Replace

    private func replaceLastInserted(raw: String, polished: String, insertMode: InsertionMode) {
        // Velg bakover (raw.count tegn), skriv inn polert tekst
        selectBackward(count: raw.count)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.insertText(polished, insertMode: insertMode, completion: nil)
        }
    }

    private func selectBackward(count: Int) {
        let src = CGEventSource(stateID: .hidSystemState)

        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(123), keyDown: true) // left arrow
            down?.flags = .maskShift
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(123), keyDown: false)
            up?.flags = .maskShift
            up?.post(tap: .cghidEventTap)
        }
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

    private func insertViaPaste(_ text: String, completion: (() -> Void)?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelaySeconds) {
            self.sendCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                completion?()
            }
        }
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp     = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
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

    private func startInternal() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do { try audioEngine.start() } catch { stopInternal(); return }

        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.finalText = result.bestTranscription.formattedString
                self.onPartial?(self.finalText)
            }

            if error != nil {
                self.stopInternal()
            }
        }
    }

    private func stopInternal() {
        isRecording = false

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        request?.endAudio()

        task?.cancel()
        task = nil
        request = nil
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
