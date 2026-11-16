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

            let actual = try #require(AppInfoFacts(metrics: metrics).sections.first?.last)

            #expect(actual.label == expectedLabel)
            #expect(actual.value == expectedValue)
        }
    }
#endif
