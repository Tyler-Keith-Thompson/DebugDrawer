#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Background Tasks install and uninstall", .timeLimit(.minutes(1)))
    struct BackgroundTasksLifecycleTests {
        private func makeDrawer(_ suite: String) throws -> DebugDrawer {
            try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))
        }

        private func makeModel(scheduler: FakeBackgroundTaskScheduler, changes: FakeBackgroundTaskChangeSource) -> BackgroundTasksModel {
            BackgroundTasksModel(declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: changes)
        }

        @Test("Unregistering the plugin removes it, stops observing the source and drops the requests read")
        func uninstallStopsObserving() async throws {
            let suite = "BackgroundTasksLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakeBackgroundTaskChangeSource()
            let scheduler = FakeBackgroundTaskScheduler(requests: [
                BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: nil, kind: .appRefresh)
            ])
            let model = makeModel(scheduler: scheduler, changes: changes)
            let sut = BackgroundTasksPlugin(model: model)
            drawer.registerGlobal(sut)
            await model.refresh()

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(changes.stops == 1)
            #expect(!changes.isObserving)
            #expect(!model.isObserving)
            #expect(model.pending == .loading)
            #expect(scheduler.requests.count == 1)
        }

        @Test("Registering the plugin again observes the source again, and a change reads the requests")
        func reinstallObservesAgain() async throws {
            let suite = "BackgroundTasksLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakeBackgroundTaskChangeSource()
            let scheduler = FakeBackgroundTaskScheduler()
            let model = makeModel(scheduler: scheduler, changes: changes)
            let sut = BackgroundTasksPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)
            let request = BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: nil, kind: .appRefresh)
            scheduler.requests = [request]

            drawer.registerGlobal(sut)
            await changes.change()

            #expect(changes.isObserving)
            #expect(model.pending == .loaded([request]))
        }

        @Test("Uninstalling twice stops the source once")
        func uninstallTwice() throws {
            let suite = "BackgroundTasksLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakeBackgroundTaskChangeSource()
            let sut = BackgroundTasksPlugin(model: makeModel(scheduler: FakeBackgroundTaskScheduler(), changes: changes))
            drawer.registerGlobal(sut)

            sut.uninstall(from: drawer)
            sut.uninstall(from: drawer)

            #expect(changes.stops == 1)
        }

        @Test("In two drawers the plugin observes until the last one uninstalls it")
        func twoDrawers() throws {
            let suite = "BackgroundTasksLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let first = try makeDrawer(suite)
            let second = try makeDrawer(suite)
            let changes = FakeBackgroundTaskChangeSource()
            let sut = BackgroundTasksPlugin(model: makeModel(scheduler: FakeBackgroundTaskScheduler(), changes: changes))
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
