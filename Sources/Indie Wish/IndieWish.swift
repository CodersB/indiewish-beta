import Foundation

// MARK: - Errors

public enum IndieWishError: Error, LocalizedError, Sendable {
    case notConfigured
    case invalidResponse
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "IndieWish is not configured. Call IndieWish.configure(...) first."
        case .invalidResponse:
            return "Invalid response from server."
        case .server(let msg):
            return msg
        }
    }
}

// MARK: - Config

public struct IndieWishConfig: Sendable {
    public let baseURL: URL
    public let boardSlug: String
    public let ingestSecret: String

    public init(baseURL: URL, boardSlug: String, ingestSecret: String) {
        self.baseURL = baseURL
        self.boardSlug = boardSlug
        self.ingestSecret = ingestSecret
    }
}

// MARK: - Core (Actor)

@available(iOS 15.0, *)
actor IndieWishCore {
    static let shared = IndieWishCore()
    private var config: IndieWishConfig?

    func configure(_ cfg: IndieWishConfig) {
        self.config = cfg
    }

    func currentConfig() throws -> IndieWishConfig {
        guard let c = config else { throw IndieWishError.notConfigured }
        return c
    }

    func isConfigured() -> Bool {
        return config != nil
    }
}

// MARK: - Public Facade

@available(iOS 15.0, *)
public enum IndieWish: Sendable {

    /// Configure IndieWish once at app start.
    public static func configure(baseURL: URL, boardSlug: String, ingestSecret: String) {
        // Detached to avoid hopping onto main actor.
        Task.detached(priority: .utility) {
            await IndieWishCore.shared.configure(
                IndieWishConfig(baseURL: baseURL, boardSlug: boardSlug, ingestSecret: ingestSecret)
            )
        }
    }

    /// Returns whether IndieWish has been configured yet.
    public static func isConfigured() async -> Bool {
        return await IndieWishCore.shared.isConfigured()
    }

    /// Send feedback to the configured IndieWish board.
    public static func sendFeedback(
        title: String,
        description: String? = nil,
        source: String = "ios"
    ) async throws {
        let cfg = try await IndieWishCore.shared.currentConfig()

        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("/api/feedback"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(cfg.ingestSecret, forHTTPHeaderField: "x-ingest-secret")

        let payload: [String: Any] = [
            "board_slug": cfg.boardSlug,
            "title": title,
            "description": description ?? "",
            "source": source
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IndieWishError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw IndieWishError.server(msg)
        }
    }
}
