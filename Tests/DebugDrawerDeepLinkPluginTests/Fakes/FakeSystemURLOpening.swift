#if DEBUG
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation

    /// A system opener that keeps every URL it's handed and opens it, or throws the error it's
    /// told to. An open of a URL in `held` waits until `release()`, so a test can order work
    /// around it.
    @MainActor
    final class FakeSystemURLOpening: SystemURLOpening {
        /// What every open throws; nil opens.
        var failure: (any Error)?
        /// URLs whose open waits until `release()`.
        var held: Set<URL>
        /// Every URL handed over, as each open starts.
        private(set) var opened: [URL] = []
        /// Every URL whose open has returned or thrown, in that order.
        private(set) var finished: [URL] = []
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(failure: (any Error)? = nil, held: Set<URL> = []) {
            self.failure = failure
            self.held = held
        }

        func open(_ url: URL) async throws {
            opened.append(url)
            if held.contains(url) {
                await withCheckedContinuation { waiting.append($0) }
            }
            finished.append(url)
            if let failure {
                throw failure
            }
        }

        /// Lets every held open go on, and holds no more.
        func release() {
            held = []
            let resumed = waiting
            waiting = []
            resumed.forEach { $0.resume() }
        }
    }
#endif
