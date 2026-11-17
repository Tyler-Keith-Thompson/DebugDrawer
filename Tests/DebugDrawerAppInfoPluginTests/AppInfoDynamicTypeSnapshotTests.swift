// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerAppInfoPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it. At 316 points, the width of the drawer
    // on an iPad and the narrowest it gets, at the default text size and an accessibility one.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the facts, the profile and the entitlements stay readable",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func factsView(size: DynamicTypeSize) throws {
            let facts = AppInfoFacts(
                sections: AppInfoFixtures.sections,
                signing: AppSigning(profile: .embedded(AppInfoFixtures.profile), entitlements: AppInfoFixtures.profile.entitlements)
            )
            let sut = AppInfoFactsView(facts: facts) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }

        @Test("In an iPad's drawer, an expired profile's warning and fields stay readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func expiredProfile(size: DynamicTypeSize) throws {
            let sut = AppInfoProvisioningSection(profile: .embedded(AppInfoFixtures.profile), isExpired: true)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }

        @Test("In an iPad's drawer, the None rows of an unsigned simulator build stay readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func unsigned(size: DynamicTypeSize) throws {
            let sut = VStack(alignment: .leading, spacing: 0) {
                AppInfoProvisioningSection(profile: .none, isExpired: false)
                AppInfoEntitlementsSection(entitlements: nil)
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }
    }
#endif
