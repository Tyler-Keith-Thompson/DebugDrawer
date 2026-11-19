#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAccessibilityPlugin
    import Foundation
    import Testing

    extension SharedAccessibilityOverrides {
        @MainActor
        @Suite(.timeLimit(.minutes(1)))
        struct AccessibilityUninstallTests {
            @Test("Removing the plugin takes it out of the drawer and clears every override")
            func uninstallClearsOverrides() throws {
                let suite = "AccessibilityUninstallTests.\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let overrides = AccessibilityOverrides(localizations: [])
                let sut = AccessibilityPlugin(model: AccessibilityModel(overrides: overrides, system: _AccessibilitySystemSettings()))
                drawer.registerGlobal(sut)
                overrides.colorScheme = .dark
                overrides.dynamicTypeSize = .accessibility3
                overrides.layoutDirection = .rightToLeft
                overrides.locale = Locale(identifier: "fr")
                overrides.reduceMotion = true
                overrides.increaseContrast = true
                overrides.boldText = true
                overrides.reduceTransparency = true
                overrides.differentiateWithoutColor = true
                overrides.invertColors = true
                let overriddenWhileInstalled = overrides.hasOverrides

                drawer.unregisterGlobal(id: sut.id)

                #expect(overriddenWhileInstalled)
                #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
                #expect(!overrides.hasOverrides)
                #expect(overrides.colorScheme == nil)
                #expect(overrides.dynamicTypeSize == nil)
                #expect(overrides.layoutDirection == nil)
                #expect(overrides.locale == nil)
                #expect(overrides.reduceMotion == nil)
                #expect(overrides.increaseContrast == nil)
                #expect(overrides.boldText == nil)
                #expect(overrides.reduceTransparency == nil)
                #expect(overrides.differentiateWithoutColor == nil)
                #expect(overrides.invertColors == nil)
                #expect(!AccessibilityOverrides.shared.hasOverrides)
            }

            @Test("Overrides stay while another drawer still holds the plugin, and clear once the last removes it")
            func lastDrawerClears() throws {
                let suite = "AccessibilityUninstallTests.\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let first = DebugDrawer(defaults: defaults)
                let second = DebugDrawer(defaults: defaults)
                let overrides = AccessibilityOverrides(localizations: [])
                // A plugin of its own in each drawer, over the same overrides, as two plugins made
                // with init() share the shared ones.
                first.registerGlobal(AccessibilityPlugin(model: AccessibilityModel(overrides: overrides, system: _AccessibilitySystemSettings())))
                second.registerGlobal(AccessibilityPlugin(model: AccessibilityModel(overrides: overrides, system: _AccessibilitySystemSettings())))
                overrides.colorScheme = .dark

                first.unregisterGlobal(id: AccessibilityPlugin().id)
                let afterFirst = overrides.colorScheme
                second.unregisterGlobal(id: AccessibilityPlugin().id)
                let actual = overrides.colorScheme

                #expect(afterFirst == .dark)
                #expect(actual == nil)
            }

            @Test("Removing the plugin twice is harmless, and overrides set after a reinstall apply until the next removal")
            func reinstallAfterUninstall() throws {
                let suite = "AccessibilityUninstallTests.\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                let overrides = AccessibilityOverrides(localizations: [])
                let sut = AccessibilityPlugin(model: AccessibilityModel(overrides: overrides, system: _AccessibilitySystemSettings()))
                drawer.registerGlobal(sut)
                drawer.unregisterGlobal(id: sut.id)
                drawer.unregisterGlobal(id: sut.id)

                drawer.registerGlobal(sut)
                overrides.boldText = true
                let whileReinstalled = overrides.boldText
                drawer.unregisterGlobal(id: sut.id)

                #expect(whileReinstalled == true)
                #expect(drawer.globalPlugins.isEmpty)
                #expect(!overrides.hasOverrides)
            }
        }
    }
#endif
