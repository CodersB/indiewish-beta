import Foundation

// MARK: - Errors

public enum IndieWishError: Error, LocalizedError, Sendable {
    case notConfigured
    case invalidResponse
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:   return "IndieWish is not configured. Call IndieWish.configure(secret:) first."
        case .invalidResponse: return "Invalid response from server."
        case .server(let msg): return msg
        }
    }
}

// MARK: - Config

public struct IndieWishConfig: Sendable {
    public let baseURL: URL
    public let ingestSecret: String
    public var cachedSlug: String? // filled after first fetch

    public init(baseURL: URL, ingestSecret: String, cachedSlug: String? = nil) {
        self.baseURL = baseURL
        self.ingestSecret = ingestSecret
        self.cachedSlug = cachedSlug
    }
}

// MARK: - Core (Actor)

@available(iOS 15.0, *)
actor IndieWishCore {
    static let shared = IndieWishCore()

    // Change this default if you ever move hosts; publish a new package version.
    private static let DEFAULT_BASE_URL = URL(string: "https://indie-wish.vercel.app")!

    private var config: IndieWishConfig?

    func configure(secret: String, overrideBaseURL: URL? = nil) {
        let base = overrideBaseURL ?? Self.DEFAULT_BASE_URL
        self.config = IndieWishConfig(baseURL: base, ingestSecret: secret, cachedSlug: nil)
    }

    func isConfigured() -> Bool { config != nil }

    func currentConfig() throws -> IndieWishConfig {
        guard let c = config else { throw IndieWishError.notConfigured }
        return c
    }

    func updateCachedSlug(_ slug: String) throws {
        guard var c = config else { throw IndieWishError.notConfigured }
        c.cachedSlug = slug
        config = c
    }

    /// Ensure we know the board slug (cached after first call)
    func ensureSlug() async throws -> String {
        if let c = config, let slug = c.cachedSlug { return slug }
        guard let c = config else { throw IndieWishError.notConfigured }

        var req = URLRequest(url: c.baseURL.appendingPathComponent("/api/ingest-info"))
        req.httpMethod = "GET"
        req.addValue(c.ingestSecret, forHTTPHeaderField: "x-ingest-secret")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw IndieWishError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw IndieWishError.server(msg)
        }

        struct Info: Decodable { let slug: String }
        let info = try JSONDecoder().decode(Info.self, from: data)
        try updateCachedSlug(info.slug)
        return info.slug
    }
}

// MARK: - Public Facade

@available(iOS 15.0, *)
public enum IndieWish: Sendable {
    /// Configure once (only the secret is required).
    public static func configure(secret: String, overrideBaseURL: URL? = nil) {
        Task.detached(priority: .utility) {
            await IndieWishCore.shared.configure(secret: secret, overrideBaseURL: overrideBaseURL)
        }
    }

    public static func isConfigured() async -> Bool {
        await IndieWishCore.shared.isConfigured()
    }

    /// Send feedback — board slug is auto-resolved by secret (cached after first call).
    public static func sendFeedback(
        title: String,
        description: String? = nil,
        source: String = "ios",
        category: String = "feature"   // "feature" or "bug"
    ) async throws {
        let cfg = try await IndieWishCore.shared.currentConfig()

        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("/api/feedback"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(cfg.ingestSecret, forHTTPHeaderField: "x-ingest-secret")

        let payload: [String: Any] = [
            "title": title,
            "description": description ?? "",
            "source": source,
            "category": category
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw IndieWishError.server(msg)
        }
    }

    /// Fetch recent public feedback (for in-app listing & upvotes)
    public static func fetchPublicItems(limit: Int = 50) async throws -> [PublicItem] {
        let cfg = try await IndieWishCore.shared.currentConfig()
        let slug = try await IndieWishCore.shared.ensureSlug()

        var url = cfg.baseURL.appendingPathComponent("/api/public-feedback")
        url.append(queryItems: [URLQueryItem(name: "slug", value: slug)])

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndieWishError.invalidResponse
        }
        struct Payload: Decodable { let items: [PublicItem] }
        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        return decoded.items
    }

    /// Public upvote (device-level; server does best-effort increment)
    public static func upvote(feedbackId: String) async throws {
        let cfg = try await IndieWishCore.shared.currentConfig()
        let slug = try await IndieWishCore.shared.ensureSlug()

        var req = URLRequest(url: cfg.baseURL.appendingPathComponent("/api/public-upvote"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "feedback_id": feedbackId,
            "board_slug": slug
        ])

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndieWishError.invalidResponse
        }
    }
}

// Small helpers

private extension URL {
    mutating func append(queryItems: [URLQueryItem]) {
        var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.queryItems = (comps.queryItems ?? []) + queryItems
        if let url = comps.url { self = url }
    }
}

// Public models (match your /api/public-feedback payload)
public struct PublicItem: Decodable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let status: String
    public let source: String?
    public let created_at: String
    public let votes: Int?
}
