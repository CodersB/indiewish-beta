import Foundation
import UIKit

// MARK: - Errors

public enum IndieWishError: Error, LocalizedError, Sendable {
    case notConfigured
    case invalidResponse
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "IndieWish is not configured. Call IndieWish.configure(secret:) first."
        case .invalidResponse:
            "Invalid response from server."
        case .server(let msg):
            msg
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

// MARK: - User Profile Manager

@available(iOS 15.0, *)
actor UserProfileManager {
    static let shared = UserProfileManager()
    
    private let userIDKey = "com.indiewish.userIdentifier"
    private let installDateKey = "com.indiewish.installDate"
    
    func getUserIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: userIDKey) {
            return existing
        }
        
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: userIDKey)
        return newID
    }
    
    func getInstallDate() -> Date {
        if let existing = UserDefaults.standard.object(forKey: installDateKey) as? Date {
            return existing
        }
        
        let installDate = Date()
        UserDefaults.standard.set(installDate, forKey: installDateKey)
        return installDate
    }
}

// MARK: - Subscription Types

public enum SubscriptionTier: String, Sendable {
    case unknown = "unknown"
    case free = "free"
    case trial = "trial"
    case paid = "paid"
    case premium = "premium"
}

public enum BillingCycle: String, Sendable {
    case monthly = "monthly"
    case yearly = "yearly"
    case lifetime = "lifetime"
    case weekly = "weekly"
}

// MARK: - User Profile (Advanced - Optional)

public struct UserProfile: Sendable {
    public let subscriptionStatus: String
    public let subscriptionExpiresAt: Date?
    public let email: String?
    public let customMetadata: [String: String]?
    
    public init(
        subscriptionStatus: String = "unknown",
        subscriptionExpiresAt: Date? = nil,
        email: String? = nil,
        customMetadata: [String: String]? = nil
    ) {
        self.subscriptionStatus = subscriptionStatus
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.email = email
        self.customMetadata = customMetadata
    }
}

// MARK: - Core (Actor)

@available(iOS 15.0, *)
actor IndieWishCore {
    static let shared = IndieWishCore()
    private static let DEFAULT_BASE_URL = URL(string: "https://indie-wish.vercel.app")!

    private var config: IndieWishConfig?
    private var userProfile: UserProfile?

    func configure(secret: String, overrideBaseURL: URL? = nil, userProfile: UserProfile? = nil) {
        let base = overrideBaseURL ?? Self.DEFAULT_BASE_URL
        self.config = IndieWishConfig(baseURL: base, ingestSecret: secret)
        self.userProfile = userProfile
    }
    
    func updateUserProfile(_ profile: UserProfile) {
        self.userProfile = profile
    }
    
    func mergeUserProfile(
        email: String?? = nil,
        subscriptionStatus: String?? = nil,
        subscriptionExpiresAt: Date?? = nil,
        customMetadata: [String: String]?? = nil
    ) {
        // Merge with existing profile (double optional allows explicit nil setting)
        let current = self.userProfile
        
        // Use double optional unwrapping: nil = don't change, .some(nil) = set to nil, .some(value) = set to value
        let newEmail = email.flatMap { $0 } ?? current?.email
        let newStatus = subscriptionStatus.flatMap { $0 } ?? current?.subscriptionStatus ?? "unknown"
        let newExpires = subscriptionExpiresAt.flatMap { $0 } ?? current?.subscriptionExpiresAt
        let newMetadata = customMetadata.flatMap { $0 } ?? current?.customMetadata
        
        self.userProfile = UserProfile(
            subscriptionStatus: newStatus,
            subscriptionExpiresAt: newExpires,
            email: newEmail,
            customMetadata: newMetadata
        )
    }
    
    func getUserProfile() -> UserProfile? {
        return userProfile
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

    func ensureSlug() async throws -> String {
        if let c = config, let slug = c.cachedSlug { return slug }
        guard let c = config else { throw IndieWishError.notConfigured }

        var req = URLRequest(url: c.baseURL.appendingPathComponent("/api/ingest-info"))
        req.httpMethod = "GET"
        req.addValue(c.ingestSecret, forHTTPHeaderField: "x-ingest-secret")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw IndieWishError.server(msg)
        }

        struct Info: Decodable { let slug: String }
        let info = try JSONDecoder().decode(Info.self, from: data)
        try updateCachedSlug(info.slug)
        return info.slug
    }
}

// MARK: - Device Metadata

@MainActor
private func captureDeviceMeta() async -> DeviceMeta {
    let bundle = Bundle.main
    let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? bundle.bundleIdentifier
        ?? "Unknown"

    let appVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    let osVersion = "iOS \(UIDevice.current.systemVersion)"
    let deviceModel = await getDeviceModelIdentifier()
    let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
    let locale = Locale.current.identifier
    let language = Locale.current.languageCode ?? "en"
    let timezone = TimeZone.current.identifier
    
    // Screen size
    let screen = UIScreen.main.bounds
    let scale = UIScreen.main.scale
    let screenWidth = Int(screen.width * scale)
    let screenHeight = Int(screen.height * scale)
    
    // User identifier and install date
    let userID = await UserProfileManager.shared.getUserIdentifier()
    let installDate = await UserProfileManager.shared.getInstallDate()

    return DeviceMeta(
        app_name: appName,
        app_version: appVersion,
        build_number: buildNumber,
        os_version: osVersion,
        device_model: deviceModel,
        device_type: deviceType,
        locale: locale,
        lang: language,
        timezone: timezone,
        screen_w: screenWidth,
        screen_h: screenHeight,
        user_identifier: userID,
        install_date: installDate
    )
}

@MainActor
private func getDeviceModelIdentifier() async -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
    
    // Detect simulator
    #if targetEnvironment(simulator)
    let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "iPad Simulator" : "iPhone Simulator"
    return "\(deviceType) (\(identifier))"
    #else
    return identifier
    #endif
}

private struct DeviceMeta: Codable, Sendable {
    let app_name: String
    let app_version: String
    let build_number: String
    let os_version: String
    let device_model: String
    let device_type: String
    let locale: String
    let lang: String
    let timezone: String
    let screen_w: Int
    let screen_h: Int
    let user_identifier: String
    let install_date: Date
}

// MARK: - Payloads & Models

private struct FeedbackPayload: Codable, Sendable {
    let title: String
    let description: String?
    let source: String
    let category: String
    
    // Device info
    let app_name: String?
    let app_version: String?
    let os_version: String?
    let device_model: String?
    let device_type: String?
    let lang: String?
    let tz: String?
    let screen_w: Int?
    let screen_h: Int?
    
    // User profile
    let user_identifier: String?
    let subscription_status: String?
    let subscription_expires_at: String?
    let install_date: String?
    let email: String?
    let custom_metadata: [String: String]?
}

public struct PublicItem: Decodable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let status: String
    public let source: String?
    public let created_at: String
    public var votes: Int?
}

public struct UpvoteResponse: Decodable, Sendable {
    public let ok: Bool
    public let votes: Int?
}

// MARK: - Public Facade

@available(iOS 15.0, *)
public enum IndieWish: Sendable {
    
    // MARK: - Simple Configuration (Recommended for most apps)
    
    /// Configure IndieWish with user information - Simple API
    /// Example: IndieWish.configure(secret: "key", email: "user@app.com", subscription: .paid, billingCycle: .monthly, amount: "$9.99")
    public static func configure(
        secret: String,
        email: String? = nil,
        subscription: SubscriptionTier = .free,
        billingCycle: BillingCycle? = nil,
        amount: String? = nil,
        overrideBaseURL: URL? = nil
    ) {
        Task.detached {
            var metadata: [String: String] = [:]
            if let cycle = billingCycle {
                metadata["billing_cycle"] = cycle.rawValue
            }
            if let amount = amount {
                metadata["amount"] = amount
            }
            
            let profile = UserProfile(
                subscriptionStatus: subscription.rawValue,
                email: email,
                customMetadata: metadata.isEmpty ? nil : metadata
            )
            
            await IndieWishCore.shared.configure(
                secret: secret,
                overrideBaseURL: overrideBaseURL,
                userProfile: profile
            )
        }
    }
    
    // MARK: - Update User Info (Flexible - update what you have)
    
    /// Update user information - Simple API (all parameters optional!)
    /// Example: IndieWish.updateUser(email: "new@email.com")  // Just email
    /// Example: IndieWish.updateUser(subscription: .premium)  // Just subscription
    /// Example: IndieWish.updateUser(email: "x@y.com", subscription: .paid, billingCycle: .monthly)  // Everything
    public static func updateUser(
        email: String? = nil,
        subscription: SubscriptionTier? = nil,
        billingCycle: BillingCycle? = nil,
        amount: String? = nil
    ) {
        Task.detached {
            var metadata: [String: String]? = nil
            if billingCycle != nil || amount != nil {
                metadata = [:]
                if let cycle = billingCycle {
                    metadata!["billing_cycle"] = cycle.rawValue
                }
                if let amt = amount {
                    metadata!["amount"] = amt
                }
            }
            
            // Merge with existing profile instead of replacing
            await IndieWishCore.shared.mergeUserProfile(
                email: .some(email),
                subscriptionStatus: subscription.map { .some($0.rawValue) },
                subscriptionExpiresAt: nil,
                customMetadata: metadata.map { .some($0) }
            )
        }
    }
    
    /// Update only email (convenience method)
    /// Example: IndieWish.setEmail("user@example.com")
    public static func setEmail(_ email: String?) {
        Task.detached {
            await IndieWishCore.shared.mergeUserProfile(email: .some(email))
        }
    }
    
    /// Update only subscription (convenience method)
    /// Example: IndieWish.setSubscription(.paid, billingCycle: .monthly, amount: "$9.99")
    public static func setSubscription(
        _ tier: SubscriptionTier,
        billingCycle: BillingCycle? = nil,
        amount: String? = nil
    ) {
        updateUser(subscription: tier, billingCycle: billingCycle, amount: amount)
    }
    
    // MARK: - Advanced API (For complex use cases)
    
    /// Advanced: Configure with custom UserProfile
    public static func configureAdvanced(
        secret: String,
        overrideBaseURL: URL? = nil,
        userProfile: UserProfile? = nil
    ) {
        Task.detached {
            await IndieWishCore.shared.configure(
                secret: secret,
                overrideBaseURL: overrideBaseURL,
                userProfile: userProfile
            )
        }
    }
    
    /// Advanced: Update with custom UserProfile
    public static func updateUserProfile(_ profile: UserProfile) {
        Task.detached {
            await IndieWishCore.shared.updateUserProfile(profile)
        }
    }

    public static func isConfigured() async -> Bool {
        await IndieWishCore.shared.isConfigured()
    }

    public static func sendFeedback(
        title: String,
        description: String? = nil,
        source: String = "ios",
        category: String = "feature"
    ) async throws {
        let cfg = try await IndieWishCore.shared.currentConfig()
        let userProfile = await IndieWishCore.shared.getUserProfile()
        let m = await captureDeviceMeta()
        
        // ISO8601 formatter
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]

        let payload = FeedbackPayload(
            title: title,
            description: description,
            source: source,
            category: category,
            app_name: m.app_name,
            app_version: m.app_version,
            os_version: m.os_version,
            device_model: m.device_model,
            device_type: m.device_type,
            lang: m.lang,
            tz: m.timezone,
            screen_w: m.screen_w,
            screen_h: m.screen_h,
            user_identifier: m.user_identifier,
            subscription_status: userProfile?.subscriptionStatus,
            subscription_expires_at: userProfile?.subscriptionExpiresAt.map { iso8601.string(from: $0) },
            install_date: iso8601.string(from: m.install_date),
            email: userProfile?.email,
            custom_metadata: userProfile?.customMetadata
        )

        var req = URLRequest(url: cfg.baseURL.appendingPathComponent("/api/feedback"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(cfg.ingestSecret, forHTTPHeaderField: "x-ingest-secret")
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw IndieWishError.server(msg)
        }
    }

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

    // MARK: - Upvote (SDK function using secret header)
    @discardableResult
    public static func upvote(feedbackId: String) async throws -> Int {
        let cfg = try await IndieWishCore.shared.currentConfig()

        var req = URLRequest(url: cfg.baseURL.appendingPathComponent("/api/public-upvote"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(cfg.ingestSecret, forHTTPHeaderField: "x-ingest-secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "feedback_id": feedbackId
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw IndieWishError.server(msg)
        }

        let decoded = try JSONDecoder().decode(UpvoteResponse.self, from: data)
        guard decoded.ok, let votes = decoded.votes else {
            throw IndieWishError.invalidResponse
        }
        return votes
    }
}

// MARK: - URL helper

private extension URL {
    mutating func append(queryItems: [URLQueryItem]) {
        var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.queryItems = (comps.queryItems ?? []) + queryItems
        if let url = comps.url { self = url }
    }
}

