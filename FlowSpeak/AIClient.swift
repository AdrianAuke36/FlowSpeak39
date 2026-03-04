import Foundation

struct PolishResponse: Decodable {
    let language: String
    let text: String
    let appliedMode: String?
    let appliedStyle: String?
}

struct RewriteResponse: Decodable {
    let language: String
    let text: String
}

enum AIClientError: LocalizedError {
    case invalidURL
    case badStatus(Int, String)
    case emptyResponse
    case cancelled
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid backend URL."
        case .badStatus(let code, let body): return "Backend returned HTTP \(code): \(body)"
        case .emptyResponse: return "Backend returned empty text."
        case .cancelled: return "Request was cancelled."
        case .transport(let msg): return "Network error: \(msg)"
        }
    }
}

final class AIClient {
    private enum Endpoint {
        static let health = "/health"
        static let ready = "/ready"
        static let version = "/version"
        static let polish = "/polish"
        static let rewrite = "/rewrite"
    }

    private enum Timeout {
        static let request: TimeInterval = 2.8
        static let resource: TimeInterval = 5.0
        static let healthRequest: TimeInterval = 2.0
        static let draftRequest: TimeInterval = 2.8
        static let rewriteRequest: TimeInterval = 3.5
    }

    static let shared = AIClient()

    var baseURLString: String = "http://127.0.0.1:3000"
    var backendToken: String = ""
    // Default to Norwegian to prevent random language drift from model outputs.
    var targetLanguage: String = "nb-NO"
    var style: WritingStyle = .clean
    var interpretationLevel: InterpretationLevel = .balanced

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = Timeout.request
        cfg.timeoutIntervalForResource = Timeout.resource
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func checkHealth() async -> Bool {
        await ensureFreshBackendTokenIfNeeded()
        guard let readyURL = URL(string: "\(baseURLString)\(Endpoint.ready)") else { return false }
        var readyRequest = URLRequest(url: readyURL)
        readyRequest.timeoutInterval = Timeout.healthRequest

        do {
            let (_, readyResponse) = try await session.data(for: readyRequest)
            guard (readyResponse as? HTTPURLResponse)?.statusCode == 200 else { return false }
        } catch {
            return false
        }

        let token = backendToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return true }
        guard let versionURL = URL(string: "\(baseURLString)\(Endpoint.version)") else { return false }

        var versionRequest = URLRequest(url: versionURL)
        versionRequest.timeoutInterval = Timeout.healthRequest
        applyAuthorizationHeader(to: &versionRequest)

        do {
            let (_, versionResponse) = try await session.data(for: versionRequest)
            return (versionResponse as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func draft(
        text: String,
        mode: DraftMode,
        ctx: FieldContext?,
        targetLanguageOverride: String? = nil
    ) async throws -> PolishResponse {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { throw AIClientError.emptyResponse }

        await ensureFreshBackendTokenIfNeeded()
        guard let url = URL(string: "\(baseURLString)\(Endpoint.polish)") else { throw AIClientError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Timeout.draftRequest
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        applyAuthorizationHeader(to: &req)

        let trimmedOverride = targetLanguageOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasExplicitTargetLanguageOverride = !trimmedOverride.isEmpty
        let effectiveTargetLanguage = resolvedTargetLanguage(from: targetLanguageOverride)
        let body = makePolishRequestBody(
            text: clean,
            mode: mode,
            ctx: ctx,
            targetLanguage: effectiveTargetLanguage,
            targetLanguageForced: hasExplicitTargetLanguageOverride
        )

        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw AIClientError.transport("No HTTP response") }

            if !(200...299).contains(http.statusCode) {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw AIClientError.badStatus(http.statusCode, bodyText)
            }

            let decoded = try JSONDecoder().decode(PolishResponse.self, from: data)
            let out = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if out.isEmpty { throw AIClientError.emptyResponse }
            return PolishResponse(
                language: decoded.language,
                text: out,
                appliedMode: decoded.appliedMode,
                appliedStyle: decoded.appliedStyle
            )
        } catch is CancellationError {
            throw AIClientError.cancelled
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw AIClientError.cancelled
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }
    }

    func rewrite(
        text: String,
        instruction: String,
        targetLanguageOverride: String? = nil,
        replyMemories: [ReplyMemoryRule] = [],
        draftReplyFromContext: Bool = false,
        modeOverride: DraftMode? = nil
    ) async throws -> RewriteResponse {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty { throw AIClientError.emptyResponse }

        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanInstruction.isEmpty {
            throw AIClientError.transport("Missing rewrite instruction.")
        }

        await ensureFreshBackendTokenIfNeeded()
        guard let url = URL(string: "\(baseURLString)\(Endpoint.rewrite)") else {
            throw AIClientError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Timeout.rewriteRequest
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        applyAuthorizationHeader(to: &req)

        let effectiveTargetLanguage = resolvedTargetLanguage(from: targetLanguageOverride)
        var body: [String: Any] = [
            "text": cleanText,
            "instruction": cleanInstruction,
            "targetLanguage": effectiveTargetLanguage,
            "style": style.rawValue
        ]
        if let modeOverride {
            body["mode"] = modeOverride.rawValue
        }
        if !replyMemories.isEmpty {
            body["replyMemories"] = replyMemories.map {
                [
                    "title": $0.title,
                    "triggers": $0.triggerText,
                    "sourceText": $0.sourceText,
                    "guidance": $0.guidance
                ]
            }
        }
        if draftReplyFromContext {
            body["draftReplyFromContext"] = true
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw AIClientError.transport("No HTTP response") }

            if !(200...299).contains(http.statusCode) {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw AIClientError.badStatus(http.statusCode, bodyText)
            }

            let decoded = try JSONDecoder().decode(RewriteResponse.self, from: data)
            let out = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if out.isEmpty { throw AIClientError.emptyResponse }
            return RewriteResponse(language: decoded.language, text: out)
        } catch is CancellationError {
            throw AIClientError.cancelled
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw AIClientError.cancelled
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }
    }

    private func makePolishRequestBody(
        text: String,
        mode: DraftMode,
        ctx: FieldContext?,
        targetLanguage: String,
        targetLanguageForced: Bool
    ) -> [String: Any] {
        [
            "text": text,
            "targetLanguage": targetLanguage,
            "targetLanguageForced": targetLanguageForced,
            "style": style.rawValue,
            "interpretationLevel": interpretationLevel.rawValue,
            "mode": mode.rawValue,
            "bundleId": ctx?.bundleId ?? "",
            "appName": ctx?.appName ?? "",
            "axRole": ctx?.axRole ?? "",
            "axSubrole": ctx?.axSubrole ?? "",
            "axDescription": ctx?.axDescription ?? "",
            "axHelp": ctx?.axHelp ?? "",
            "axTitle": ctx?.axTitle ?? "",
            "axPlaceholder": ctx?.axPlaceholder ?? "",
            "fieldContext": ctx?.axValuePreview ?? "",
            "browserURL": ctx?.browserURL ?? ""
        ]
    }

    private func resolvedTargetLanguage(from overrideCode: String?) -> String {
        let explicit = overrideCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }

        let configured = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? "nb-NO" : configured
    }

    private func applyAuthorizationHeader(to request: inout URLRequest) {
        let token = backendToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func ensureFreshBackendTokenIfNeeded() async {
        _ = await AppSettings.shared.refreshSupabaseSessionIfNeeded(force: false)
        let tokenFromSettings = await MainActor.run { AppSettings.shared.backendToken }
        if backendToken != tokenFromSettings {
            backendToken = tokenFromSettings
        }
    }
}
