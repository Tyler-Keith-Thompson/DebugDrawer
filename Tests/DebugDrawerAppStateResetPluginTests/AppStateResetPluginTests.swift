#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAppStateResetPlugin
    import Testing

    @MainActor
    @Suite
    struct AppStateResetPluginTests {
        @Test("The plugin is Reset App State, in Storage, with a header accessory and no HUD")
        func identity() throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let sut = AppStateResetPlugin(model: AppStateResetModel(appState: seeded.appState, process: FakeAppProcess()))

            #expect(sut.id == "AppStateResetPlugin")
            #expect(sut.title == "Reset App State")
            #expect(sut.category == "Storage")
            #expect(sut.icon == "arrow.counterclockwise.circle")
            #expect(AnyDebugDrawerPlugin(sut).headerAccessory != nil)
            #expect(!AnyDebugDrawerPlugin(sut).hasHUD)
        }

        @Test("Every category has a title and a symbol of its own")
        func categories() {
            let titles = ResetCategory.allCases.map(\.title)
            let symbols = ResetCategory.allCases.map(\.systemImage)

            #expect(titles == ["UserDefaults", "Keychain", "Files", "Caches", "Cookies", "URL cache", "App cleanup"])
            #expect(Set(symbols).count == ResetCategory.allCases.count)
        }
    }
#endif
