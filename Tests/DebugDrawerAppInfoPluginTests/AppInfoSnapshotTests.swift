// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerAppInfoPlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. At 316
    // points, the width of the drawer on an iPad and the narrowest it gets. macOS doesn't scale
    // text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoSnapshotTests {
        @Test(
            "The facts view: Build with the commit, branch and CI build, Runtime, Environment, the profile, the entitlements, then the buttons",
            arguments: [ColorScheme.light, .dark]
        )
        func factsView(colorScheme: ColorScheme) throws {
            let facts = AppInfoFacts(
                sections: AppInfoFixtures.sections,
                signing: AppSigning(profile: .embedded(AppInfoFixtures.profile), entitlements: AppInfoFixtures.profile.entitlements)
            )
            let sut = AppInfoFactsView(facts: facts) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("An expired profile: the Expired warning above its name, team, dates and devices", arguments: [ColorScheme.light, .dark])
        func expiredProfile(colorScheme: ColorScheme) throws {
            let sut = AppInfoProvisioningSection(profile: .embedded(AppInfoFixtures.profile), isExpired: true)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("No profile and no entitlements: a None row in each section", arguments: [ColorScheme.light, .dark])
        func unsigned(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 0) {
                AppInfoProvisioningSection(profile: .none, isExpired: false)
                AppInfoEntitlementsSection(entitlements: nil)
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
