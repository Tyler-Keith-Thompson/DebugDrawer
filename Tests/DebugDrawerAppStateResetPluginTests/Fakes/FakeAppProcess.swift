#if DEBUG
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset

    /// A process that records each restart instead of ending, and can fail to relaunch.
    @MainActor
    final class FakeAppProcess: AppProcess {
        let restartStyle: RestartStyle
        /// What a restart throws; `nil` to succeed.
        var failure: RelaunchFailure?
        /// Run as a restart begins, to see what had happened by then.
        var onRestart: () -> Void = {}
        private(set) var restarts = 0

        init(_ restartStyle: RestartStyle = .quit) {
            self.restartStyle = restartStyle
        }

        func restart() async throws(RelaunchFailure) {
            onRestart()
            restarts += 1
            if let failure { throw failure }
        }
    }
#endif
