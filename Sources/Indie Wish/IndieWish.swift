import Foundation
import UIKit

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
    public var cachedSlug: String?

    public init(baseURL: URL, ingestSecret: String, cachedSlug: String? = nil) {
        self.baseURL = baseURL
        self.ingestSecret = ingestSecret
        self.cachedSlug = cachedSlug
    }
}

// MARK: - Core Actor

@available(iOS 15.0, *)
actor IndieWishCore {
    static let shared = IndieWishCore()
    private static let DEFAULT_BASE_URL = URL(string: "https://indie-wish.vercel.app")!
    private var config: IndieWishConfig?

    func configure(secret: String, overrideBaseURL: URL? = nil) {
        let base = overrideBaseURL ?? Self.DEFAULT_BASE_URL
        self.config = IndieWishConfig(baseURL: base, ingestSecret: secret)
    }

    func currentConfig() throws -> IndieWishConfig {
        guard let c = config else { throw IndieWishError.notConfigured }
        return c
    }

    func updateCachedSlug(_ slug: String) throws {
        guard var c = config else { throw IndieWishError.notConfigured }
        c.cachedSlug = slug
        config = c
    }

    func ensureSlug() async throws -> String {
        if let c = config, let slug = c.cachedSlug { return slug }
        guard let c = config else { throw IndieWishError.notConfigured }

        var req = URLRequest(url: c.baseURL.appendingPathComponent("/api/ingest-info"))
        req.httpMethod = "GET"
        req.addValue(c.ingestSecret, forHTTPHeaderField: "x-ingest-secret")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndieWishError.invalidResponse
        }

        struct Info: Decodable { let slug: String }
        let info = try JSONDecoder().decode(Info.self, from: data)
        try updateCachedSlug(info.slug)
        return info.slug
    }
}

// MARK: - Public API

@available(iOS 15.0, *)
public enum IndieWish: Sendable {
    
    // MARK: Configuration
    public static func configure(secret: String, overrideBaseURL: URL? = nil) {
        Task.detached(priority: .utility) {
            await IndieWishCore.shared.configure(secret: secret, overrideBaseURL: overrideBaseURL)
        }
    }
    
    public static func sendFeedback(
        title: String,
        description: String? = nil,
        source: String = "ios",
        category: String = "feature"
    ) async throws {
        let cfg = try await IndieWishCore.shared.currentConfig()
        let url = cfg.baseURL.appendingPathComponent("/api/feedback")

        // Now Sendable, so this await is OK
        let metadata = await captureMetadata()

        var payload: [String: Any] = [
            "title": title,
            "description": description ?? "",
            "source": source,
            "category": category
        ]
        // Merge String:String into String:Any
        for (k, v) in metadata { payload[k] = v }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(cfg.ingestSecret, forHTTPHeaderField: "x-ingest-secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw IndieWishError.server(msg)
        }
    }
    
    // MARK: Public listing & upvote
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
        return try JSONDecoder().decode(Payload.self, from: data).items
    }
    
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
    
    @MainActor
    private static func captureMetadata() -> [String: String] {
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
        bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown"
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        let locale = Locale.current.identifier
        let timezone = TimeZone.current.identifier
        
        return [
            "app_name": appName,
            "app_version": appVersion,
            "build_number": buildNumber,
            "os_version": osVersion,
            "device_model": deviceModel,
            "locale": locale,
            "timezone": timezone
        ]
    }
}

// MARK: - Helpers

private extension URL {
    mutating func append(queryItems: [URLQueryItem]) {
        var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.queryItems = (comps.queryItems ?? []) + queryItems
        if let url = comps.url { self = url }
    }
}

// MARK: - Models

public struct PublicItem: Decodable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let status: String
    public let source: String?
    public let created_at: String
    public let votes: Int?
}
