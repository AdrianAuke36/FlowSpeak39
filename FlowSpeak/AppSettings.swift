import Foundation
import Combine

enum InsertionMode: String, CaseIterable, Identifiable {
    case pasteOnly
    case typeOnly
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pasteOnly: return "Paste (Cmd+V)"
        case .typeOnly:  return "Type (compat)"
        case .hybrid:    return "Hybrid (paste → fallback type)"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var globalMode: InsertionMode {
        didSet { UserDefaults.standard.set(globalMode.rawValue, forKey: "globalMode") }
    }

    // bundleId -> modeRawValue
    @Published var overrides: [String: String] {
        didSet { saveOverrides() }
    }

    private init() {
        let rawGlobal = UserDefaults.standard.string(forKey: "globalMode") ?? InsertionMode.pasteOnly.rawValue
        self.globalMode = InsertionMode(rawValue: rawGlobal) ?? .pasteOnly

        if let data = UserDefaults.standard.data(forKey: "overrides"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.overrides = dict
        } else {
            // Pre-tunet for deg:
            self.overrides = [
                "com.openai.chatgpt": InsertionMode.pasteOnly.rawValue,          // ChatGPT desktop
                "com.tinyspeck.slackmacgap": InsertionMode.pasteOnly.rawValue,   // Slack
                "notion.id": InsertionMode.typeOnly.rawValue,                    // Notion
                "com.microsoft.teams": InsertionMode.typeOnly.rawValue,          // Teams
                "com.microsoft.teams2": InsertionMode.typeOnly.rawValue,         // New Teams
                "com.google.Chrome": InsertionMode.typeOnly.rawValue,            // Chrome (Gmail/web)
                "com.apple.Safari": InsertionMode.typeOnly.rawValue,
                "com.microsoft.edgemac": InsertionMode.typeOnly.rawValue
            ]
        }
    }

    func mode(for bundleId: String?) -> InsertionMode {
        guard let bundleId else { return globalMode }
        if let raw = overrides[bundleId], let m = InsertionMode(rawValue: raw) { return m }
        return globalMode
    }

    func setOverride(bundleId: String, mode: InsertionMode) {
        overrides[bundleId] = mode.rawValue
    }

    func removeOverride(bundleId: String) {
        overrides.removeValue(forKey: bundleId)
    }

    private func saveOverrides() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: "overrides")
        }
    }
}
//
//  AppSettings.swift
//  FlowSpeak
//
//  Created by Adrian Auke on 20/02/2026.
//

