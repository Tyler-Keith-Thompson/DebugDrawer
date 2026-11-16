#if DEBUG
    import Foundation

    /// The `BGTaskScheduler` calls the plugin makes: the shared scheduler in production
    /// (`SystemBackgroundTaskSchedulerClient`), a fake the test steers in tests.
    @MainActor
    protocol BackgroundTaskSchedulerClient {
        /// The requests submitted and not yet run.
        func pendingTaskRequests() async -> [BackgroundTaskRequest]

        /// Submits a request of `kind` for `identifier`, to run no sooner than
        /// `earliestBeginDate`, replacing any pending one for the identifier. A processing request
        /// waits for no network or external power.
        ///
        /// - Throws: `BackgroundTaskSubmitFailure` when the scheduler refuses the request.
        func submit(identifier: String, kind: BackgroundTaskKind, earliestBeginDate: Date) async throws(BackgroundTaskSubmitFailure)

        /// Cancels the pending request for `identifier`.
        func cancel(taskRequestWithIdentifier identifier: String)

        /// Cancels every pending request.
        func cancelAllTaskRequests()
    }
#endif
