#if DEBUG
    @testable import DebugDrawerRemote
    import Network

    /// A browser that browses nothing: it counts starts and cancels, and hands the browser the
    /// services a test says it found.
    @MainActor
    final class FakeServiceBrowser: ServiceBrowser {
        private(set) var startCount = 0
        private(set) var cancelCount = 0
        private var results: (@MainActor ([BrowsedService]) -> Void)?

        func start(_ results: @escaping @MainActor ([BrowsedService]) -> Void) {
            startCount += 1
            self.results = results
        }

        func cancel() {
            cancelCount += 1
            results = nil
        }

        /// Reports `services` as everything found now.
        func find(_ services: [BrowsedService]) {
            results?(services)
        }
    }
#endif
