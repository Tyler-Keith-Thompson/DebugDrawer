#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAccessibilityPlugin
    import Testing

    /// Every suite that sets `AccessibilityOverrides.shared`, or draws a view that follows it, is
    /// nested in this one. It is serialized, so no test sees another's overrides, and each test
    /// starts and ends with the overrides reset.
    @Suite(.serialized, .resetsAccessibilityOverrides)
    enum SharedAccessibilityOverrides {}

    /// Resets `AccessibilityOverrides.shared` before and after each test it applies to.
    struct ResetsAccessibilityOverrides: SuiteTrait, TestTrait, TestScoping {
        var isRecursive: Bool { true }

        func provideScope(
            for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
        ) async throws {
            await Self.reset()
            do {
                try await function()
            } catch {
                await Self.reset()
                throw error
            }
            await Self.reset()
        }

        @MainActor
        private static func reset() {
            AccessibilityOverrides.shared.reset()
        }
    }

    extension Trait where Self == ResetsAccessibilityOverrides {
        static var resetsAccessibilityOverrides: Self { Self() }
    }

    extension SharedAccessibilityOverrides {
        @MainActor
        @Suite(.timeLimit(.minutes(1)))
        struct AccessibilityPluginTests {
            @Test("With nothing set, no override has a value and none is reported")
            func overridesDefault() {
                let overrides = AccessibilityOverrides.shared
                #expect(overrides.colorScheme == nil)
                #expect(overrides.dynamicTypeSize == nil)
                #expect(overrides.layoutDirection == nil)
                #expect(overrides.locale == nil)
                #expect(!overrides.hasOverrides)
            }

            @Test("Reset clears the color scheme and Dynamic Type overrides, and no override is reported after it")
            func overridesReset() {
                let overrides = AccessibilityOverrides.shared
                overrides.colorScheme = .dark
                overrides.dynamicTypeSize = .xLarge
                #expect(overrides.hasOverrides)

                overrides.reset()
                #expect(!overrides.hasOverrides)
                #expect(overrides.colorScheme == nil)
                #expect(overrides.dynamicTypeSize == nil)
            }

            @Test("The available locales can be read, even when the test bundle has no localizations")
            func availableLocales() {
                let overrides = AccessibilityOverrides.shared
                // At minimum, the app's base localization should be present
                // (may be empty in test target, which is fine)
                _ = overrides.availableLocales
            }

            @Test("The plugin is titled Accessibility, with the accessibility icon")
            func pluginConformance() {
                let plugin = AccessibilityPlugin()
                #expect(plugin.title == "Accessibility")
                #expect(plugin.icon == "accessibility")
            }
        }
    }
#endif
