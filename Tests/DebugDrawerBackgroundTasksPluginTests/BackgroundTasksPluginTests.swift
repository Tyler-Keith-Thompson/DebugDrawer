#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BackgroundTasksPluginTests {
        @Test("The plugin is Background Tasks, in the App category, offers Refresh and Cancel All, and adds to bug reports")
        func identity() {
            let model = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []),
                client: FakeBackgroundTaskScheduler(), changes: FakeBackgroundTaskChangeSource()
            )

            let sut = BackgroundTasksPlugin(model: model)

            #expect(sut.id == "BackgroundTasksPlugin")
            #expect(sut.title == "Background Tasks")
            #expect(sut.category == "App")
            #expect(sut.icon == "clock.arrow.circlepath")
            #expect(sut.actions.map(\.title) == ["Refresh background tasks", "Cancel all background task requests"])
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The Cancel All search action cancels every request")
        func cancelAllAction() {
            let scheduler = FakeBackgroundTaskScheduler()
            let model = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )
            let sut = BackgroundTasksPlugin(model: model)

            sut.actions[1].perform()

            #expect(scheduler.cancelledAll == 1)
        }

        @Test("The bug report gets background-tasks.txt: the modes, the identifiers, and each request with its kind and date in UTC")
        func report() throws {
            let declaration = BackgroundTaskDeclaration(
                identifiers: [PermittedIdentifier("com.example.refresh"), PermittedIdentifier("com.example.cleanup")],
                kinds: [.appRefresh, .processing]
            )
            let pending = PendingRequestsState.loaded([
                BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: Date(timeIntervalSince1970: 1_800_000_000), kind: .appRefresh),
                BackgroundTaskRequest(
                    id: "com.example.cleanup", earliestBeginDate: nil,
                    kind: .processing(requiresNetworkConnectivity: true, requiresExternalPower: false)
                )
            ])
            let expected = """
            Background modes: fetch, processing
            Permitted identifiers (2):
              com.example.refresh
              com.example.cleanup
            Pending requests (2):
              com.example.refresh
                kind: App Refresh
                earliest begin: 2027-01-15T08:00:00Z
              com.example.cleanup
                kind: Processing · Needs network
                earliest begin: none
            """
            var actual = DebugDrawerReport()

            BackgroundTasksPlugin.contribute(declaration: declaration, pending: pending, to: &actual)

            let file = try #require(actual.files.first)
            #expect(actual.files.map(\.name) == ["background-tasks.txt"])
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("With nothing declared and nothing read yet the report says so")
        func reportEmpty() {
            let expected = """
            Background modes: none
            Permitted identifiers (0):
            Pending requests: not read yet
            """

            let actual = BackgroundTasksPlugin.text(declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), pending: .loading)

            #expect(actual == expected)
        }
    }
#endif
