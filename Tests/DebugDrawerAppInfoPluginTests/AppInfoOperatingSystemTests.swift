#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite("App Info's OS row")
    @MainActor
    struct AppInfoOperatingSystemTests {
        @Test("The OS row is labelled with the name of the platform the app runs on, and shows its version")
        func operatingSystemRowNamesThePlatform() throws {
            #if os(macOS)
                let expectedLabel = "macOS"
            #elseif targetEnvironment(macCatalyst)
                let expectedLabel = "macOS (Mac Catalyst)"
            #else
                let expectedLabel = "iOS"
            #endif
            let expectedValue = ProcessInfo.processInfo.operatingSystemVersionString
            let metrics = AppMetrics(processStart: nil, now: Date.init)

            let facts = AppInfoFacts(metrics: metrics, buildMetadata: AppInfoBuildMetadata(), signing: AppSigning(profile: .none, entitlements: nil))

            let actual = try #require(facts.sections.first { $0.title == "Environment" }?.facts.first)
            #expect(actual.label == expectedLabel)
            #expect(actual.value == expectedValue)
        }
    }
#endif
