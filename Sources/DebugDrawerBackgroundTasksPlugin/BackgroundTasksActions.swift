#if DEBUG
    /// What `BackgroundTasksView`'s buttons do, each handed in by the caller.
    struct BackgroundTasksActions {
        var refresh: () -> Void = {}
        var schedule: (String, BackgroundTaskKind) -> Void = { _, _ in }
        var cancel: (BackgroundTaskRequest.ID) -> Void = { _ in }
        var cancelAll: () -> Void = {}
    }
#endif
