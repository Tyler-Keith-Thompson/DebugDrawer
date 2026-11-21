#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Analytics install and uninstall")
    struct AnalyticsLifecycleTests {
        @Test("Unregistering the plugin removes it, stops reading the log, drops its events and clears the badge")
        func uninstallStopsReading() throws {
            let suite = "AnalyticsLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let log = AnalyticsEventLog(capacity: 10)
            log.record(name: "launched", properties: [:], source: nil)
            var counts: [Int] = []
            let model = AnalyticsEventsModel(log: log) { counts.append($0) }
            let sut = AnalyticsPlugin(model: model)
            drawer.registerGlobal(sut)

            drawer.unregisterGlobal(id: sut.id)
            log.record(name: "after", properties: [:], source: nil)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(!log.isObserved)
            #expect(!model.isReading)
            #expect(model.events.isEmpty)
            #expect(counts == [1, 0])
        }

        // No test in this process installs Analytics on the shared drawer (the install tests run
        // in child processes), so reading its badge here sees only what this test's plugin did.
        @Test("Installed only in a drawer of its own, the plugin badges that drawer as its unseen count changes, and never the shared one")
        func badgesItsOwnDrawer() throws {
            let suite = "AnalyticsLifecycleTests.badgesItsOwnDrawer.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let log = AnalyticsEventLog(capacity: 10)
            log.record(name: "launched", properties: [:], source: nil)
            let model = AnalyticsEventsModel(log: log)
            let sut = AnalyticsPlugin(model: model)
            let beforeInstall = drawer.badges[sut.id]

            drawer.registerGlobal(sut)
            let installed = drawer.badges[sut.id]
            log.record(name: "purchase", properties: [:], source: nil)
            // What the log's observer does on the main actor after the event; called here so the
            // test needn't wait for it.
            model.reload()
            let changed = drawer.badges[sut.id]
            let sharedWhileInstalled = DebugDrawer.shared.badges[sut.id]
            drawer.unregisterGlobal(id: sut.id)
            log.record(name: "after", properties: [:], source: nil)
            model.reload()

            #expect(beforeInstall == nil)
            #expect(installed == 1)
            #expect(changed == 2)
            #expect(sharedWhileInstalled == nil)
            #expect(drawer.badges[sut.id] == nil)
            #expect(DebugDrawer.shared.badges[sut.id] == nil)
        }

        @Test("Registering the plugin again reads the log again, events recorded meanwhile included")
        func reinstallReadsAgain() throws {
            let suite = "AnalyticsLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let log = AnalyticsEventLog(capacity: 10)
            let model = AnalyticsEventsModel(log: log)
            let sut = AnalyticsPlugin(model: model)
            drawer.registerGlobal(sut)
            log.record(name: "before", properties: [:], source: nil)
            drawer.unregisterGlobal(id: sut.id)
            log.record(name: "meanwhile", properties: [:], source: nil)

            drawer.registerGlobal(sut)

            #expect(log.isObserved)
            #expect(model.events.map(\.name) == ["meanwhile", "before"])
        }

        @Test("Uninstalling twice is harmless")
        func uninstallTwice() throws {
            let suite = "AnalyticsLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let log = AnalyticsEventLog(capacity: 10)
            var counts: [Int] = []
            let model = AnalyticsEventsModel(log: log) { counts.append($0) }
            let sut = AnalyticsPlugin(model: model)
            drawer.registerGlobal(sut)

            sut.uninstall(from: drawer)
            sut.uninstall(from: drawer)

            #expect(!log.isObserved)
            #expect(counts.isEmpty)
        }

        @Test("In two drawers the plugin reads the log until the last one uninstalls it")
        func twoDrawers() throws {
            let suite = "AnalyticsLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let first = DebugDrawer(defaults: defaults)
            let second = DebugDrawer(defaults: defaults)
            let log = AnalyticsEventLog(capacity: 10)
            let model = AnalyticsEventsModel(log: log)
            let sut = AnalyticsPlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.unregisterGlobal(id: sut.id)
            let readingWithOneLeft = model.isReading
            second.unregisterGlobal(id: sut.id)

            #expect(readingWithOneLeft)
            #expect(!model.isReading)
        }

        @Test("An older model's uninstall leaves the observer a newer model set on the log")
        func olderUninstallKeepsNewerObserver() throws {
            let suite = "AnalyticsLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let log = AnalyticsEventLog(capacity: 10)
            let older = AnalyticsPlugin(model: AnalyticsEventsModel(log: log))
            drawer.registerGlobal(older)
            let newer = AnalyticsEventsModel(log: log)

            drawer.unregisterGlobal(id: older.id)

            #expect(log.isObserved)
            #expect(newer.isReading)
        }
    }
#endif
