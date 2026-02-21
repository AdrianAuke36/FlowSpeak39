import Foundation

struct PolishResponse: Decodable {
    let language: String
    let text: String
}

enum AIClientError: LocalizedError {
    case invalidURL
    case badStatus(Int, String)
    case emptyResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid backend URL."
        case .badStatus(let code, let body): return "Backend returned HTTP \(code): \(body)"
        case .emptyResponse: return "Backend returned empty text."
        case .transport(let msg): return "Network error: \(msg)"
        }
    }
}

final class AIClient {
    static let shared = AIClient()

    var baseURLString: String = "http://127.0.0.1:3000"
    var targetLanguage: String = ""

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 7
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func draft(text: String, mode: DraftMode, ctx: FieldContext?) async throws -> PolishResponse {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { throw AIClientError.emptyResponse }

        guard let url = URL(string: "\(baseURLString)/polish") else { throw AIClientError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let body: [String: Any] = [
            "text": clean,
            "targetLanguage": targetLanguage,
            "mode": mode.rawValue,

            // valgfritt, men nyttig for logging/debug på server
            "bundleId": ctx?.bundleId ?? "",
            "appName": ctx?.appName ?? "",
            "axRole": ctx?.axRole ?? "",
            "axSubrole": ctx?.axSubrole ?? "",
            "axDescription": ctx?.axDescription ?? "",
            "axHelp": ctx?.axHelp ?? "",
            "axTitle": ctx?.axTitle ?? "",
            "axPlaceholder": ctx?.axPlaceholder ?? ""
        ]

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
            return PolishResponse(language: decoded.language, text: out)
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }
    }
}
