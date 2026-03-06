import Foundation
import Combine

struct AppLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: AppLogLevel
    let message: String
    let metadata: [String: String]

    var summaryLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let base = "[\(formatter.string(from: timestamp))] \(level.rawValue) \(message)"
        guard !metadata.isEmpty else { return base }
        let meta = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(base) | \(meta)"
    }
}

enum AppLogLevel: String, Codable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    @Published private(set) var entries: [AppLogEntry]

    private let maxEntries = 400
    private let storageKey = "appDebugLogEntries"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AppLogEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    var entryCount: Int {
        entries.count
    }

    var latestSummary: String? {
        entries.last?.summaryLine
    }

    func record(_ level: AppLogLevel = .info, _ message: String, metadata: [String: String] = [:]) {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { return }

        let cleanMetadata = metadata.reduce(into: [String: String]()) { result, pair in
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            result[pair.key] = value
        }

        let entry = AppLogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            message: cleanMessage,
            metadata: cleanMetadata
        )

        DispatchQueue.main.async {
            var updated = self.entries
            updated.append(entry)
            if updated.count > self.maxEntries {
                updated.removeFirst(updated.count - self.maxEntries)
            }
            self.entries = updated
            self.persist()
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries = []
            UserDefaults.standard.removeObject(forKey: self.storageKey)
        }
    }

    func exportText() -> String {
        entries.map(\.summaryLine).joined(separator: "\n")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
