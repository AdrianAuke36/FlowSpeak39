import Combine
import Foundation

enum DictationMode: String, Codable {
    case email, chat, note, generic

    var label: String { rawValue }
}

struct DictationEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let mode: DictationMode
    let appName: String

    init(id: UUID = UUID(), date: Date = Date(), text: String, mode: DictationMode, appName: String) {
        self.id = id
        self.date = date
        self.text = text
        self.mode = mode
        self.appName = appName
    }
}

final class DictationHistory: ObservableObject {
    static let shared = DictationHistory()

    @Published private(set) var entries: [DictationEntry] = []
    @Published private(set) var maxEntries: Int

    private enum Storage {
        static let key = "dictation_history"
        static let maxEntriesKey = "dictation_history_max_entries"
        static let defaultMaxEntries = 200
        static let minMaxEntries = 20
        static let maxMaxEntries = 2000
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuredMaxEntries = defaults.integer(forKey: Storage.maxEntriesKey)
        if configuredMaxEntries == 0 {
            self.maxEntries = Storage.defaultMaxEntries
        } else {
            self.maxEntries = min(
                Storage.maxMaxEntries,
                max(Storage.minMaxEntries, configuredMaxEntries)
            )
        }
        load()
        applyMaxEntriesLimit()
    }

    func add(text: String, mode: DictationMode, appName: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = DictationEntry(text: trimmed, mode: mode, appName: appName)
        entries.insert(entry, at: 0)
        applyMaxEntriesLimit()
        save()
    }

    func setMaxEntries(_ value: Int) {
        let normalized = min(Storage.maxMaxEntries, max(Storage.minMaxEntries, value))
        guard normalized != maxEntries else { return }
        maxEntries = normalized
        defaults.set(normalized, forKey: Storage.maxEntriesKey)
        applyMaxEntriesLimit()
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    var todayEntries: [DictationEntry] {
        entries.filter { Calendar.current.isDateInToday($0.date) }
    }

    var wordCount: Int {
        totalWordCount(in: entries)
    }

    var todayWordCount: Int {
        totalWordCount(in: todayEntries)
    }

    private func totalWordCount(in source: [DictationEntry]) -> Int {
        source.reduce(into: 0) { partial, entry in
            partial += entry.text.split(whereSeparator: \.isWhitespace).count
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Storage.key)
    }

    private func load() {
        guard let data = defaults.data(forKey: Storage.key),
              let decoded = try? JSONDecoder().decode([DictationEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func applyMaxEntriesLimit() {
        guard entries.count > maxEntries else { return }
        entries.removeLast(entries.count - maxEntries)
    }
}

// MARK: - DraftMode → DictationMode konvertering
extension DictationMode {
    init(from draftMode: DraftMode) {
        switch draftMode {
        case .emailBody, .emailSubject: self = .email
        case .chatMessage:              self = .chat
        case .note:                     self = .note
        case .generic:                  self = .generic
        }
    }
}
