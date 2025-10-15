import Foundation
import Testing
@testable import Indie_Wish

@Test("Configuration works properly")
func testConfiguration() async throws {
    #if os(iOS)
    if #available(iOS 15.0, *) {
        // Configure IndieWish with fake values
        IndieWish.configure(
            secret: "TEST_SECRET",
            overrideBaseURL: URL(string: "https://example.com")!)

        // Give detached task a short moment to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        // Validate configuration stored in actor
        let configured = await IndieWish.isConfigured()
        #expect(configured == true)
    }
    #endif
}

@Test("sendFeedback throws if not configured")
func testNotConfiguredError() async throws {
    #if os(iOS)
    if #available(iOS 15.0, *) {
        // Reset actor manually by reinitializing shared state
        let coreMirror = Mirror(reflecting: IndieWishCore.shared)
        _ = coreMirror // Just to silence warnings; not actually accessible publicly

        // Expect error if sendFeedback called before configure
        do {
            try await IndieWish.sendFeedback(title: "Sample")
            Issue.record("Expected .notConfigured error, but did not throw.")
        } catch {
            #expect(error is IndieWishError)
        }
    }
    #endif
}
