// The examples of the kit's "Building a Sidecar App" article, as written there (the app without
// `@main`, which a test target can't hold).

#if DEBUG && os(macOS)
    import DebugDrawerSidecarKit
    import SwiftUI
    import Testing

    struct CompanySidecar: App {
        var body: some Scene {
            WindowGroup {
                DebugDrawerSidecarView(groupIdentifier: "group.com.example.debug")
            }
        }
    }

    /// The company's grant service the article's sidecar asks for a session's grant.
    @MainActor
    final class GrantService {
        static let shared = GrantService()

        func grant(for bundleIdentifier: String) async throws -> String {
            "grant-for-\(bundleIdentifier)"
        }
    }

    @MainActor
    struct SidecarAppExamples {
        let severalGroups = DebugDrawerSidecarView(groupIdentifiers: ["group.com.example.shop.debug", "group.com.example.wallet.debug"])

        let granted = DebugDrawerSidecarView(groupIdentifier: "group.com.example.debug", sessionDuration: 10 * 60) { app in
            try await GrantService.shared.grant(for: app.bundleIdentifier)
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarAppExamplesTests {
        @Test("The article's grant service answers with a grant for the bundle ID it is given")
        func grantServiceAnswersForTheApp() async throws {
            let expected = "grant-for-com.example.shop"
            _ = SidecarAppExamples()

            let actual = try await GrantService.shared.grant(for: "com.example.shop")

            #expect(actual == expected)
        }
    }
#endif
