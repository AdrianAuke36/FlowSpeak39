//
//  AppSettings.swift
//  FlowSpeak
//
//  Created by Adrian Auke on 20/02/2026.
//

import Foundation
import Combine
import AVFoundation
import Security

enum AppLanguage: String, CaseIterable, Identifiable {
    case norwegian = "nb-NO"
    case english = "en-US"

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .norwegian: return "Norsk"
        case .english:   return "English"
        }
    }

    var speechLocaleIdentifier: String {
        switch self {
        case .norwegian: return "nb-NO"
        case .english:   return "en-US"
        }
    }

    var targetLanguageCode: String {
        rawValue
    }
}

enum WritingStyle: String, CaseIterable, Identifiable {
    case clean
    case formal
    case casual
    case excited

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .clean: return "Clean"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .excited: return "Excited"
        }
    }
}

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

struct MicrophoneOption: Identifiable, Hashable {
    static let systemDefaultID = "__system_default__"

    let id: String
    let name: String
}

enum MicrophoneCatalog {
    static func availableOptions() -> [MicrophoneOption] {
        var deduped: [String: MicrophoneOption] = [:]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        for device in discovery.devices {
            deduped[device.uniqueID] = MicrophoneOption(id: device.uniqueID, name: device.localizedName)
        }

        let sorted = deduped.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let defaultDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "System Default"
        let system = MicrophoneOption(
            id: MicrophoneOption.systemDefaultID,
            name: "System Default (\(defaultDeviceName))"
        )

        return [system] + sorted
    }
}

final class AppSettings: ObservableObject {
    private enum StorageKey {
        static let appLanguage = "appLanguage"
        static let translationTargetLanguage = "translationTargetLanguage"
        static let globalMode = "globalMode"
        static let writingStyle = "writingStyle"
        static let selectedMicrophoneUID = "selectedMicrophoneUID"
        static let backendBaseURL = "backendBaseURL"
        static let backendToken = "backendToken"
        static let supabaseProjectURL = "supabaseProjectURL"
        static let supabaseAnonKey = "supabaseAnonKey"
        static let supabaseUserEmail = "supabaseUserEmail"
        static let supabaseSessionExpiresAt = "supabaseSessionExpiresAt"
        static let supabaseRefreshToken = "supabaseRefreshToken"
        static let hasCompletedSetupOnboarding = "hasCompletedSetupOnboarding"
        static let overrides = "overrides"
    }

    private static let defaultOverrides: [String: String] = [
        "com.openai.chatgpt": InsertionMode.pasteOnly.rawValue,          // ChatGPT desktop
        "com.tinyspeck.slackmacgap": InsertionMode.pasteOnly.rawValue,   // Slack
        "notion.id": InsertionMode.typeOnly.rawValue,                    // Notion
        "com.microsoft.teams": InsertionMode.typeOnly.rawValue,          // Teams
        "com.microsoft.teams2": InsertionMode.typeOnly.rawValue,         // New Teams
        "com.google.Chrome": InsertionMode.typeOnly.rawValue,            // Chrome (Gmail/web)
        "com.apple.Safari": InsertionMode.typeOnly.rawValue,
        "com.microsoft.edgemac": InsertionMode.typeOnly.rawValue
    ]

    static let shared = AppSettings()

    static let defaultBackendBaseURL = "http://127.0.0.1:3000"
    static let defaultSupabaseProjectURL = ""
    private static let infoBackendBaseURLKey = "FlowSpeakBackendBaseURL"
    private static let infoSupabaseProjectURLKey = "FlowSpeakSupabaseProjectURL"
    private static let infoSupabaseAnonKeyKey = "FlowSpeakSupabaseAnonKey"

    @Published var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: StorageKey.appLanguage) }
    }

    @Published var translationTargetLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(translationTargetLanguage.rawValue, forKey: StorageKey.translationTargetLanguage) }
    }

    @Published var globalMode: InsertionMode {
        didSet { UserDefaults.standard.set(globalMode.rawValue, forKey: StorageKey.globalMode) }
    }

    @Published var writingStyle: WritingStyle {
        didSet { UserDefaults.standard.set(writingStyle.rawValue, forKey: StorageKey.writingStyle) }
    }

    @Published var selectedMicrophoneUID: String {
        didSet { UserDefaults.standard.set(selectedMicrophoneUID, forKey: StorageKey.selectedMicrophoneUID) }
    }

    @Published var backendBaseURL: String {
        didSet {
            let normalized = Self.normalizedBackendBaseURL(backendBaseURL)
            if backendBaseURL != normalized {
                backendBaseURL = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: StorageKey.backendBaseURL)
        }
    }

    @Published var backendToken: String {
        didSet {
            let normalized = backendToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if backendToken != normalized {
                backendToken = normalized
                return
            }
            if normalized.isEmpty {
                UserDefaults.standard.removeObject(forKey: StorageKey.backendToken)
            } else {
                UserDefaults.standard.set(normalized, forKey: StorageKey.backendToken)
            }
        }
    }

    @Published var supabaseProjectURL: String {
        didSet {
            let normalized = Self.normalizedSupabaseProjectURL(supabaseProjectURL)
            if supabaseProjectURL != normalized {
                supabaseProjectURL = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: StorageKey.supabaseProjectURL)
        }
    }

    @Published var supabaseAnonKey: String {
        didSet {
            let normalized = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if supabaseAnonKey != normalized {
                supabaseAnonKey = normalized
                return
            }
            if normalized.isEmpty {
                UserDefaults.standard.removeObject(forKey: StorageKey.supabaseAnonKey)
            } else {
                UserDefaults.standard.set(normalized, forKey: StorageKey.supabaseAnonKey)
            }
        }
    }

    @Published var supabaseUserEmail: String {
        didSet {
            let normalized = supabaseUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            if supabaseUserEmail != normalized {
                supabaseUserEmail = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: StorageKey.supabaseUserEmail)
        }
    }

    @Published var supabaseSessionExpiresAt: Date? {
        didSet {
            if let expiry = supabaseSessionExpiresAt {
                UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: StorageKey.supabaseSessionExpiresAt)
            } else {
                UserDefaults.standard.removeObject(forKey: StorageKey.supabaseSessionExpiresAt)
            }
        }
    }

    @Published var hasCompletedSetupOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedSetupOnboarding, forKey: StorageKey.hasCompletedSetupOnboarding) }
    }

    // bundleId -> modeRawValue
    @Published var overrides: [String: String] {
        didSet { saveOverrides() }
    }

    // Keep the refresh token in memory after launch so SwiftUI auth checks do not keep hitting Keychain.
    private var cachedSupabaseRefreshToken: String

    private init() {
        let rawLanguage = UserDefaults.standard.string(forKey: StorageKey.appLanguage) ?? AppLanguage.norwegian.rawValue
        self.appLanguage = AppLanguage(rawValue: rawLanguage) ?? .norwegian

        let rawTranslateLanguage = UserDefaults.standard.string(forKey: StorageKey.translationTargetLanguage) ?? AppLanguage.english.rawValue
        self.translationTargetLanguage = AppLanguage(rawValue: rawTranslateLanguage) ?? .english

        let rawGlobal = UserDefaults.standard.string(forKey: StorageKey.globalMode) ?? InsertionMode.pasteOnly.rawValue
        self.globalMode = InsertionMode(rawValue: rawGlobal) ?? .pasteOnly

        let rawStyle = UserDefaults.standard.string(forKey: StorageKey.writingStyle) ?? WritingStyle.clean.rawValue
        self.writingStyle = WritingStyle(rawValue: rawStyle) ?? .clean

        let rawMicrophone = UserDefaults.standard.string(forKey: StorageKey.selectedMicrophoneUID) ?? MicrophoneOption.systemDefaultID
        self.selectedMicrophoneUID = rawMicrophone

        let bootstrapBackendURL = Self.bootstrapBackendBaseURL()
        let rawBackendBaseURL = UserDefaults.standard.string(forKey: StorageKey.backendBaseURL) ?? bootstrapBackendURL
        self.backendBaseURL = Self.normalizedBackendBaseURL(rawBackendBaseURL)

        let envToken = ProcessInfo.processInfo.environment["FLOWSPEAK_BACKEND_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedToken = UserDefaults.standard.string(forKey: StorageKey.backendToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.backendToken = storedToken.isEmpty ? envToken : storedToken

        let bootstrapSupabaseProjectURL = Self.bootstrapSupabaseProjectURL()
        let rawSupabaseProjectURL = UserDefaults.standard.string(forKey: StorageKey.supabaseProjectURL) ?? bootstrapSupabaseProjectURL
        self.supabaseProjectURL = Self.normalizedSupabaseProjectURL(rawSupabaseProjectURL)

        let envSupabaseAnonKey = ProcessInfo.processInfo.environment["FLOWSPEAK_SUPABASE_ANON_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let infoSupabaseAnonKey = Self.infoString(forKey: Self.infoSupabaseAnonKeyKey)
        let storedSupabaseAnonKey = UserDefaults.standard.string(forKey: StorageKey.supabaseAnonKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedSupabaseAnonKey.isEmpty {
            self.supabaseAnonKey = storedSupabaseAnonKey
        } else if !envSupabaseAnonKey.isEmpty {
            self.supabaseAnonKey = envSupabaseAnonKey
        } else {
            self.supabaseAnonKey = infoSupabaseAnonKey
        }

        self.supabaseUserEmail = UserDefaults.standard.string(forKey: StorageKey.supabaseUserEmail) ?? ""
        if let rawExpiry = UserDefaults.standard.object(forKey: StorageKey.supabaseSessionExpiresAt) as? Double {
            self.supabaseSessionExpiresAt = Date(timeIntervalSince1970: rawExpiry)
        } else {
            self.supabaseSessionExpiresAt = nil
        }
        if UserDefaults.standard.object(forKey: StorageKey.hasCompletedSetupOnboarding) == nil {
            self.hasCompletedSetupOnboarding = true
        } else {
            self.hasCompletedSetupOnboarding = UserDefaults.standard.bool(forKey: StorageKey.hasCompletedSetupOnboarding)
        }
        self.cachedSupabaseRefreshToken = UserDefaults.standard.string(forKey: StorageKey.supabaseRefreshToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let data = UserDefaults.standard.data(forKey: StorageKey.overrides),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.overrides = dict
        } else {
            self.overrides = Self.defaultOverrides
        }

        sanitizeSelectedMicrophone()
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
            UserDefaults.standard.set(data, forKey: StorageKey.overrides)
        }
    }

    func sanitizeSelectedMicrophone() {
        if selectedMicrophoneUID == MicrophoneOption.systemDefaultID {
            return
        }

        let knownIDs = Set(MicrophoneCatalog.availableOptions().map(\.id))
        if !knownIDs.contains(selectedMicrophoneUID) {
            selectedMicrophoneUID = MicrophoneOption.systemDefaultID
        }
    }

    private static func normalizedBackendBaseURL(_ value: String) -> String {
        var out = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasSuffix("/") {
            out.removeLast()
        }
        return out.isEmpty ? defaultBackendBaseURL : out
    }

    private static func normalizedSupabaseProjectURL(_ value: String) -> String {
        var out = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasSuffix("/") {
            out.removeLast()
        }
        return out
    }

    private static func bootstrapBackendBaseURL() -> String {
        let envValue = ProcessInfo.processInfo.environment["FLOWSPEAK_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !envValue.isEmpty {
            return normalizedBackendBaseURL(envValue)
        }

        let infoValue = infoString(forKey: infoBackendBaseURLKey)
        if !infoValue.isEmpty {
            return normalizedBackendBaseURL(infoValue)
        }

        return defaultBackendBaseURL
    }

    private static func bootstrapSupabaseProjectURL() -> String {
        let envValue = ProcessInfo.processInfo.environment["FLOWSPEAK_SUPABASE_PROJECT_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !envValue.isEmpty {
            return normalizedSupabaseProjectURL(envValue)
        }

        let infoValue = infoString(forKey: infoSupabaseProjectURLKey)
        if !infoValue.isEmpty {
            return normalizedSupabaseProjectURL(infoValue)
        }

        return defaultSupabaseProjectURL
    }

    private static func infoString(forKey key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // A refresh token is enough to consider the user "logged in" because we can mint a new JWT on demand.
    var hasSupabaseSession: Bool {
        !cachedSupabaseRefreshToken.isEmpty
    }

    // The home view uses this to decide whether to show the auth gate or the main app shell.
    var hasAuthenticatedSession: Bool {
        !backendToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasSupabaseSession
    }

    var isSupabaseConfigured: Bool {
        !Self.normalizedSupabaseProjectURL(supabaseProjectURL).isEmpty &&
        !supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func signInSupabase(email: String, password: String) async throws {
        let credentials = try validatedAuthCredentials(email: email, password: password)

        let response = try await requestSupabaseToken(
            grantType: "password",
            payload: ["email": credentials.email, "password": credentials.password]
        )
        guard applySupabaseSession(response) else {
            throw AppSettingsError.auth("Supabase did not return a usable session.")
        }
        supabaseUserEmail = credentials.email
    }

    @MainActor
    func signUpSupabase(
        email: String,
        password: String,
        fullName: String? = nil,
        country: String? = nil,
        marketingOptIn: Bool = false
    ) async throws -> SupabaseSignUpResult {
        let credentials = try validatedAuthCredentials(email: email, password: password)
        let cleanFullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanCountry = country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var payload: [String: Any] = [
            "email": credentials.email,
            "password": credentials.password
        ]

        if !cleanFullName.isEmpty || !cleanCountry.isEmpty || marketingOptIn {
            payload["data"] = [
                "full_name": cleanFullName,
                "country": cleanCountry,
                "marketing_opt_in": marketingOptIn
            ]
        }

        let response = try await requestSupabaseAuth(
            path: "/auth/v1/signup",
            payload: payload
        )
        supabaseUserEmail = credentials.email

        if applySupabaseSession(response) {
            hasCompletedSetupOnboarding = false
            return .signedIn
        }

        return .confirmationRequired
    }

    @MainActor
    func refreshSupabaseSessionIfNeeded(force: Bool = false) async -> Bool {
        let refreshToken = cachedSupabaseRefreshToken
        guard !refreshToken.isEmpty else { return false }

        if !force,
           let expiry = supabaseSessionExpiresAt,
           expiry.timeIntervalSinceNow > 90,
           !backendToken.isEmpty {
            return true
        }

        do {
            let response = try await requestSupabaseToken(
                grantType: "refresh_token",
                payload: ["refresh_token": refreshToken]
            )
            return applySupabaseSession(response)
        } catch {
            return false
        }
    }

    @MainActor
    func signOutSupabaseSession() {
        cachedSupabaseRefreshToken = ""
        UserDefaults.standard.removeObject(forKey: StorageKey.supabaseRefreshToken)
        supabaseSessionExpiresAt = nil
        backendToken = ""
    }

    @MainActor
    func completeSetupOnboarding() {
        hasCompletedSetupOnboarding = true
    }

    @discardableResult
    private func applySupabaseSession(_ response: SupabaseAuthResponse) -> Bool {
        let accessToken = response.access_token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refreshToken = response.refresh_token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty, !refreshToken.isEmpty else { return false }

        backendToken = accessToken
        cachedSupabaseRefreshToken = refreshToken
        UserDefaults.standard.set(refreshToken, forKey: StorageKey.supabaseRefreshToken)
        let expiresIn = max(30, response.expires_in ?? 0)
        supabaseSessionExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        if let email = response.user?.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            supabaseUserEmail = email
        }
        return true
    }

    private func requestSupabaseToken(grantType: String, payload: [String: Any]) async throws -> SupabaseAuthResponse {
        try await requestSupabaseAuth(
            path: "/auth/v1/token?grant_type=\(grantType)",
            payload: payload
        )
    }

    // Sign-in, sign-up and refresh all go through the same Supabase REST contract, only the path differs.
    private func requestSupabaseAuth(path: String, payload: [String: Any]) async throws -> SupabaseAuthResponse {
        let baseURL = Self.normalizedSupabaseProjectURL(supabaseProjectURL)
        let anonKey = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            throw AppSettingsError.auth("Missing Supabase project URL.")
        }
        guard !anonKey.isEmpty else {
            throw AppSettingsError.auth("Missing Supabase anon key.")
        }
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw AppSettingsError.auth("Invalid Supabase project URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AppSettingsError.auth("No HTTP response from Supabase.")
        }
        if !(200...299).contains(http.statusCode) {
            throw AppSettingsError.auth(
                "Supabase auth failed (\(http.statusCode)). \(supabaseErrorMessage(from: data))"
            )
        }
        do {
            return try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        } catch {
            throw AppSettingsError.auth("Invalid Supabase auth response.")
        }
    }

    private func validatedAuthCredentials(email: String, password: String) throws -> (email: String, password: String) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanEmail.isEmpty else {
            throw AppSettingsError.auth("Missing email.")
        }
        guard !cleanPassword.isEmpty else {
            throw AppSettingsError.auth("Missing password.")
        }

        return (email: cleanEmail, password: cleanPassword)
    }

    private func supabaseErrorMessage(from data: Data) -> String {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["msg", "message", "error_description", "error"]
            for key in keys {
                if let value = payload[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }

        let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bodyText.isEmpty ? "Unknown auth error." : bodyText
    }
}

enum SupabaseSignUpResult {
    case signedIn
    case confirmationRequired
}

private struct SupabaseAuthResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
    let token_type: String?
    let user: SupabaseUserInfo?
}

private struct SupabaseUserInfo: Decodable {
    let email: String?
}

private enum AppSettingsError: LocalizedError {
    case auth(String)

    var errorDescription: String? {
        switch self {
        case .auth(let message):
            return message
        }
    }
}

private enum KeychainSecretStore {
    private static let service = "Adrian.FlowSpeak"
    private static let backendTokenAccount = "backend_api_token"
    private static let supabaseAnonKeyAccount = "supabase_anon_key"
    private static let supabaseRefreshTokenAccount = "supabase_refresh_token"

    static func saveBackendToken(_ token: String) {
        if token.isEmpty {
            delete(account: backendTokenAccount)
            return
        }

        let encoded = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backendTokenAccount
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: encoded
        ]

        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = encoded
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func loadBackendToken() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backendTokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func saveSupabaseAnonKey(_ value: String) {
        save(secret: value, account: supabaseAnonKeyAccount)
    }

    static func loadSupabaseAnonKey() -> String {
        loadSecret(account: supabaseAnonKeyAccount)
    }

    static func saveSupabaseRefreshToken(_ value: String) {
        save(secret: value, account: supabaseRefreshTokenAccount)
    }

    static func loadSupabaseRefreshToken() -> String {
        loadSecret(account: supabaseRefreshTokenAccount)
    }

    private static func save(secret: String, account: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(account: account)
            return
        }

        let encoded = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: encoded
        ]

        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = encoded
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func loadSecret(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
