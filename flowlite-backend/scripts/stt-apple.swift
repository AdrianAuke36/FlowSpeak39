import Foundation
import Speech

struct RunResult: Codable {
    let ok: Bool
    let run: Int
    let latencyMs: Double?
    let transcript: String
    let error: String?
}

struct NumberSummary: Codable {
    let count: Int
    let avg: Double
    let p50: Double
    let p90: Double
    let p95: Double
    let min: Double
    let max: Double
}

struct Summary: Codable {
    let successCount: Int
    let failureCount: Int
    let latencyMs: NumberSummary
}

struct Output: Codable {
    struct FileInfo: Codable {
        let path: String
        let bytes: Int
    }

    struct Config: Codable {
        let locale: String
        let runs: Int
        let timeoutMs: Int
        let onDeviceOnly: Bool
    }

    let provider: String
    let file: FileInfo
    let config: Config
    let summary: Summary
    let sampleTranscript: String
    let runs: [RunResult]
}

func argValue(_ name: String, default fallback: String = "") -> String {
    let args = CommandLine.arguments
    guard let idx = args.firstIndex(of: "--\(name)"), idx + 1 < args.count else {
        return fallback
    }
    return args[idx + 1]
}

func hasFlag(_ name: String) -> Bool {
    CommandLine.arguments.contains("--\(name)")
}

func fail(_ message: String) -> Never {
    fputs("stt-apple failed: \(message)\n", stderr)
    exit(1)
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = Int(max(0, min(Double(sorted.count - 1), ceil((p / 100.0) * Double(sorted.count)) - 1)))
    return sorted[index]
}

func summarize(_ values: [Double]) -> NumberSummary {
    guard !values.isEmpty else {
        return NumberSummary(count: 0, avg: 0, p50: 0, p90: 0, p95: 0, min: 0, max: 0)
    }
    let sum = values.reduce(0, +)
    return NumberSummary(
        count: values.count,
        avg: (sum / Double(values.count) * 100).rounded() / 100,
        p50: (percentile(values, 50) * 100).rounded() / 100,
        p90: (percentile(values, 90) * 100).rounded() / 100,
        p95: (percentile(values, 95) * 100).rounded() / 100,
        min: ((values.min() ?? 0) * 100).rounded() / 100,
        max: ((values.max() ?? 0) * 100).rounded() / 100
    )
}

func printHelp() {
    let help = """
Usage:
  swift scripts/stt-apple.swift --file /abs/path/audio.m4a

Options:
  --file <path>         Required audio file path.
  --locale <id>         Apple speech locale. Default: nb-NO
  --runs <n>            Number of runs. Default: 3
  --timeout-ms <n>      Timeout per run. Default: 60000
  --on-device-only      Require on-device recognition only (optional)
  --out <path>          Save JSON report to path (optional)
  --help                Show this help
"""
    print(help)
}

let filePath = argValue("file")
if hasFlag("help") || hasFlag("h") {
    printHelp()
    exit(0)
}
if filePath.isEmpty {
    fail("Missing --file")
}

let localeID = argValue("locale", default: "nb-NO")
let runs = max(1, Int(argValue("runs", default: "3")) ?? 3)
let timeoutMs = max(1000, Int(argValue("timeout-ms", default: "60000")) ?? 60000)
let onDeviceOnly = hasFlag("on-device-only")
let outPath = argValue("out")

let fileURL = URL(fileURLWithPath: filePath)
guard FileManager.default.fileExists(atPath: fileURL.path) else {
    fail("File not found: \(fileURL.path)")
}

let fileAttributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
let fileSize = (fileAttributes?[.size] as? NSNumber)?.intValue ?? 0

let authStatus = SFSpeechRecognizer.authorizationStatus()
guard authStatus == .authorized else {
    fail(
        "Speech authorization is not granted for this process (status=\(authStatus.rawValue)). " +
        "CLI Swift processes may be blocked by macOS privacy rules. " +
        "Run Apple-side timing via BlueSpeak debug logs (STT capture finished) instead."
    )
}

guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
    fail("Unable to create SFSpeechRecognizer for locale \(localeID)")
}

var runResults: [RunResult] = []

for i in 1...runs {
    autoreleasepool {
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        if onDeviceOnly {
            request.requiresOnDeviceRecognition = true
        }

        let done = DispatchSemaphore(value: 0)
        let startedAt = Date()

        var transcript = ""
        var runError: String?

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                transcript = result.bestTranscription.formattedString
                if result.isFinal {
                    done.signal()
                    return
                }
            }
            if let error {
                runError = error.localizedDescription
                done.signal()
            }
        }

        let waitResult = done.wait(timeout: .now() + .milliseconds(timeoutMs))
        let elapsedMs = Date().timeIntervalSince(startedAt) * 1000

        if waitResult == .timedOut {
            task.cancel()
            runResults.append(
                RunResult(ok: false, run: i, latencyMs: nil, transcript: "", error: "timeout after \(timeoutMs)ms")
            )
            return
        }

        if let runError {
            runResults.append(
                RunResult(ok: false, run: i, latencyMs: nil, transcript: transcript, error: runError)
            )
        } else {
            runResults.append(
                RunResult(
                    ok: !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    run: i,
                    latencyMs: (elapsedMs * 100).rounded() / 100,
                    transcript: transcript,
                    error: transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "empty transcript" : nil
                )
            )
        }
        task.cancel()
    }
}

let success = runResults.filter { $0.ok }
let latencies = success.compactMap { $0.latencyMs }
let output = Output(
    provider: "apple_speech",
    file: .init(path: fileURL.path, bytes: fileSize),
    config: .init(locale: localeID, runs: runs, timeoutMs: timeoutMs, onDeviceOnly: onDeviceOnly),
    summary: .init(
        successCount: success.count,
        failureCount: runResults.count - success.count,
        latencyMs: summarize(latencies)
    ),
    sampleTranscript: success.first?.transcript ?? "",
    runs: runResults
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
guard let data = try? encoder.encode(output), let json = String(data: data, encoding: .utf8) else {
    fail("Failed to encode JSON output")
}

print(json)

if !outPath.isEmpty {
    do {
        try data.write(to: URL(fileURLWithPath: outPath))
        fputs("Saved report to \(outPath)\n", stderr)
    } catch {
        fputs("Could not save report to \(outPath): \(error.localizedDescription)\n", stderr)
    }
}
