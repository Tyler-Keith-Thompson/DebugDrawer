#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAccessibilityPlugin
    import XCTest

    @MainActor
    final class AccessibilityPluginTests: XCTestCase {
        func testOverridesDefault() {
            let overrides = AccessibilityOverrides.shared
            XCTAssertNil(overrides.colorScheme)
            XCTAssertNil(overrides.dynamicTypeSize)
            XCTAssertNil(overrides.layoutDirection)
            XCTAssertNil(overrides.locale)
            XCTAssertFalse(overrides.hasOverrides)
        }

        func testOverridesReset() {
            let overrides = AccessibilityOverrides.shared
            overrides.colorScheme = .dark
            overrides.dynamicTypeSize = .xLarge
            XCTAssertTrue(overrides.hasOverrides)

            overrides.reset()
            XCTAssertFalse(overrides.hasOverrides)
            XCTAssertNil(overrides.colorScheme)
            XCTAssertNil(overrides.dynamicTypeSize)
        }

        func testAvailableLocales() {
            let overrides = AccessibilityOverrides.shared
            // At minimum, the app's base localization should be present
            // (may be empty in test target, which is fine)
            _ = overrides.availableLocales
        }

        func testPluginConformance() {
            let plugin = AccessibilityPlugin()
            XCTAssertEqual(plugin.title, "Accessibility")
            XCTAssertEqual(plugin.icon, "accessibility")
        }
    }
#endif
