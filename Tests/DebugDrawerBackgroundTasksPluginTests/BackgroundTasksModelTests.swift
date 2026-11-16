#if DEBUG
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BackgroundTasksModelTests {
        @Test("Before the first read nothing is listed; a read lists the scheduler's pending requests")
        func refresh() async {
            let requests = [
                BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: Date(timeIntervalSince1970: 1_800_000_000), kind: .appRefresh),
                BackgroundTaskRequest(
                    id: "com.example.cleanup", earliestBeginDate: nil,
                    kind: .processing(requiresNetworkConnectivity: true, requiresExternalPower: true)
                )
            ]
            let scheduler = FakeBackgroundTaskScheduler(requests: requests)
            let sut = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )
            let before = sut.pending

            await sut.refresh()

            #expect(before == .loading)
            #expect(sut.pending == .loaded(requests))
        }

        @Test("A change the source reports reads the requests again")
        func change() async {
            let scheduler = FakeBackgroundTaskScheduler()
            let changes = FakeBackgroundTaskChangeSource()
            let sut = BackgroundTasksModel(declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: changes)
            await sut.refresh()
            let expected = [BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: nil, kind: .appRefresh)]
            scheduler.requests = expected

            await changes.change()

            #expect(sut.pending == .loaded(expected))
            #expect(scheduler.reads == 2)
        }

        @Test("Schedule submits a request of the kind asked for that may begin now, then lists it")
        func schedule() async {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let scheduler = FakeBackgroundTaskScheduler()
            let sut = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("com.example.cleanup")], kinds: [.processing]),
                client: scheduler, changes: FakeBackgroundTaskChangeSource(), now: { now }
            )
            let expectedSubmission = FakeBackgroundTaskScheduler.Submission(
                identifier: "com.example.cleanup", kind: .processing, earliestBeginDate: now
            )
            let expectedPending = [BackgroundTaskRequest(
                id: "com.example.cleanup", earliestBeginDate: now,
                kind: .processing(requiresNetworkConnectivity: false, requiresExternalPower: false)
            )]

            await sut.schedule("com.example.cleanup", as: .processing)

            #expect(scheduler.submissions == [expectedSubmission])
            #expect(sut.pending == .loaded(expectedPending))
            #expect(sut.schedule == .idle)
        }

        @Test("A request the scheduler refuses shows the failure on its identifier, and the requests are read again",
              arguments: [BackgroundTaskSubmitFailure.unavailable, .notPermitted, .tooManyPendingTaskRequests, .other(message: "No")])
        func refused(failure: BackgroundTaskSubmitFailure) async {
            let scheduler = FakeBackgroundTaskScheduler()
            scheduler.submitFailure = failure
            let sut = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("com.example.refresh")], kinds: [.appRefresh]),
                client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )
            let expected = ScheduleState.failed(identifier: "com.example.refresh", kind: .appRefresh, failure: failure)

            await sut.schedule("com.example.refresh", as: .appRefresh)

            #expect(sut.schedule == expected)
            #expect(sut.pending == .loaded([]))
            #expect(scheduler.submissions.isEmpty)
        }

        @Test("A later Schedule that succeeds clears the earlier refusal")
        func refusalCleared() async {
            let scheduler = FakeBackgroundTaskScheduler()
            scheduler.submitFailure = .unavailable
            let sut = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("a")], kinds: [.appRefresh]),
                client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )
            await sut.schedule("a", as: .appRefresh)
            scheduler.submitFailure = nil

            await sut.schedule("a", as: .appRefresh)

            #expect(sut.schedule == .idle)
        }

        @Test("Cancel cancels the one request through the scheduler and drops it from the list")
        func cancel() async {
            let refresh = BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: nil, kind: .appRefresh)
            let cleanup = BackgroundTaskRequest(
                id: "com.example.cleanup", earliestBeginDate: nil, kind: .processing(requiresNetworkConnectivity: false, requiresExternalPower: false)
            )
            let scheduler = FakeBackgroundTaskScheduler(requests: [refresh, cleanup])
            let sut = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )
            await sut.refresh()

            sut.cancel("com.example.refresh")

            #expect(scheduler.cancelled == ["com.example.refresh"])
            #expect(scheduler.cancelledAll == 0)
            #expect(sut.pending == .loaded([cleanup]))
        }

        @Test("Cancel All cancels every request through the scheduler and empties the list")
        func cancelAll() async {
            let scheduler = FakeBackgroundTaskScheduler(requests: [
                BackgroundTaskRequest(id: "a", earliestBeginDate: nil, kind: .appRefresh),
                BackgroundTaskRequest(id: "b", earliestBeginDate: nil, kind: .appRefresh)
            ])
            let sut = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )
            await sut.refresh()

            sut.cancelAll()

            #expect(scheduler.cancelledAll == 1)
            #expect(scheduler.cancelled.isEmpty)
            #expect(sut.pending == .loaded([]))
        }

        @Test("Cancelling before the first read asks the scheduler and lists nothing yet")
        func cancelBeforeRead() {
            let scheduler = FakeBackgroundTaskScheduler()
            let sut = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )

            sut.cancelAll()

            #expect(scheduler.cancelledAll == 1)
            #expect(sut.pending == .loading)
        }
    }
#endif
