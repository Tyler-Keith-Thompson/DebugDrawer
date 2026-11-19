#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Notifications install and uninstall", .timeLimit(.minutes(1)))
    struct NotificationsLifecycleTests {
        private func makeDrawer(_ suite: String) throws -> DebugDrawer {
            try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))
        }

        @Test("Unregistering the plugin removes it, stops observing the source and drops the center read; the token stays")
        func uninstallStopsObserving() async throws {
            let suite = "NotificationsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakeNotificationChangeSource()
            let model = NotificationsModel(
                registration: .registered(deviceToken: Data([0x01])), client: FakeNotificationCenter(authorization: .authorized), changes: changes
            )
            let sut = NotificationsPlugin(model: model)
            drawer.registerGlobal(sut)
            await model.refresh()

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(changes.stops == 1)
            #expect(!changes.isObserving)
            #expect(!model.isObserving)
            #expect(model.center == .loading)
            #expect(model.registration == .registered(deviceToken: Data([0x01])))
        }

        @Test("Registering the plugin again observes the source again, and a change reads the center")
        func reinstallObservesAgain() async throws {
            let suite = "NotificationsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakeNotificationChangeSource()
            let center = FakeNotificationCenter(authorization: .denied)
            let model = NotificationsModel(registration: .notRegistered, client: center, changes: changes)
            let sut = NotificationsPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)
            center.authorization = .authorized

            drawer.registerGlobal(sut)
            await changes.change()

            guard case let .loaded(snapshot) = model.center else {
                Issue.record("Expected a loaded center, got \(model.center)")
                return
            }
            #expect(changes.isObserving)
            #expect(snapshot.settings.authorization == .authorized)
        }

        @Test("Uninstalling twice stops the source once")
        func uninstallTwice() throws {
            let suite = "NotificationsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakeNotificationChangeSource()
            let sut = NotificationsPlugin(model: NotificationsModel(
                registration: .notRegistered, client: FakeNotificationCenter(authorization: .authorized), changes: changes
            ))
            drawer.registerGlobal(sut)

            sut.uninstall(from: drawer)
            sut.uninstall(from: drawer)

            #expect(changes.stops == 1)
        }

        @Test("In two drawers the plugin observes until the last one uninstalls it")
        func twoDrawers() throws {
            let suite = "NotificationsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let first = try makeDrawer(suite)
            let second = try makeDrawer(suite)
            let changes = FakeNotificationChangeSource()
            let sut = NotificationsPlugin(model: NotificationsModel(
                registration: .notRegistered, client: FakeNotificationCenter(authorization: .authorized), changes: changes
            ))
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.unregisterGlobal(id: sut.id)
            let isObservingWithOneLeft = changes.isObserving
            second.unregisterGlobal(id: sut.id)

            #expect(isObservingWithOneLeft)
            #expect(!changes.isObserving)
        }
    }
#endif
