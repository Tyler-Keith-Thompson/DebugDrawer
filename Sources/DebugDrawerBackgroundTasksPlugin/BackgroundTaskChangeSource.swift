#if DEBUG
    /// Tells the plugin when the pending requests may have changed: the app becoming active in
    /// production (`AppActivationChangeSource`), a fake the test fires in tests.
    @MainActor
    protocol BackgroundTaskChangeSource {
        /// Calls `onChange` each time the requests may have changed from now on, awaiting each call.
        func observe(_ onChange: @escaping @MainActor () async -> Void)
    }
#endif
