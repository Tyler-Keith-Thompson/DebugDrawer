#if DEBUG
    import Combine
    @testable import DebugDrawer
    import SwiftUI
    import Testing

    struct TestPlugin: DebugDrawerPlugin {
        var title: String
        var icon = "gear"
        var body: some View { Text("test") }
    }

    // Each test makes a drawer of its own over a UserDefaults suite named for the test, removed
    // when the test ends, so the tests run alongside the others and share nothing. A UUID follows
    // the test's name, here and in every core suite: test processes running at once (Bazel's
    // --runs_per_test, two checkouts) share the preferences daemon, which keeps a suite by its
    // name, so one run's removal would empty another's suite.
    @MainActor
    @Suite("DebugDrawer registry")
    struct DebugDrawerTests {
        @Test("Registering a global plugin lists it")
        func registerGlobalPlugin() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            #expect(sut.globalPlugins.isEmpty)

            sut.registerGlobal(TestPlugin(title: "A"))

            #expect(sut.globalPlugins.count == 1)
            #expect(sut.globalPlugins.first?.title == "A")
        }

        @Test("A second global plugin with the same ID is ignored")
        func duplicateGlobalIgnored() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)

            sut.registerGlobal(TestPlugin(title: "A"))
            sut.registerGlobal(TestPlugin(title: "A")) // same ID (type name)

            #expect(sut.globalPlugins.count == 1)
        }

        @Test("Unregistering a global plugin removes it")
        func unregisterGlobal() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            sut.registerGlobal(TestPlugin(title: "A"))

            sut.unregisterGlobal(id: "DebugDrawerTests.TestPlugin")

            #expect(sut.globalPlugins.isEmpty)
        }

        @Test("A local plugin is removed by the token its registration returned")
        func localPluginToken() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let token = sut.registerLocal(TestPlugin(title: "Local"))
            #expect(sut.localPlugins.count == 1)

            sut.unregisterLocal(id: "DebugDrawerTests.TestPlugin", token: token)

            #expect(sut.localPlugins.isEmpty)
        }

        @Test("A stale token does not remove a newer registration of the same plugin")
        func staleTokenNoOp() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let oldToken = sut.registerLocal(TestPlugin(title: "Local"))
            let newToken = sut.registerLocal(TestPlugin(title: "Updated"))

            sut.unregisterLocal(id: "DebugDrawerTests.TestPlugin", token: oldToken)
            #expect(sut.localPlugins.count == 1)

            sut.unregisterLocal(id: "DebugDrawerTests.TestPlugin", token: newToken)
            #expect(sut.localPlugins.isEmpty)
        }

        @Test("The drawer has plugins once one is registered")
        func hasPlugins() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            #expect(!sut.hasPlugins)

            sut.registerGlobal(TestPlugin(title: "A"))

            #expect(sut.hasPlugins)
        }

        @Test("Toggling opens a closed drawer and closes an open one")
        func toggle() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            #expect(!sut.isOpen)

            sut.toggle()
            #expect(sut.isOpen)

            sut.toggle()
            #expect(!sut.isOpen)
        }

        @Test("Opening opens the drawer, and opening it again leaves it open")
        func openTwice() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            #expect(!sut.isOpen)

            sut.open()
            #expect(sut.isOpen)

            sut.open()
            #expect(sut.isOpen)
        }

        @Test("Closing closes the drawer, and closing it again leaves it closed")
        func closeTwice() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            sut.open()
            #expect(sut.isOpen)

            sut.close()
            #expect(!sut.isOpen)

            sut.close()
            #expect(!sut.isOpen)
        }

        @Test("Opening and closing publish each change through $isOpen, and repeating either publishes nothing more")
        func openAndClosePublish() throws {
            let suite = "DebugDrawerTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let expected: [Bool] = [true, false]
            var actual: [Bool] = []
            let subscription = sut.$isOpen.dropFirst().sink { actual.append($0) }

            sut.open()
            sut.open()
            sut.close()
            sut.close()

            subscription.cancel()
            #expect(actual == expected)
        }
    }
#endif
