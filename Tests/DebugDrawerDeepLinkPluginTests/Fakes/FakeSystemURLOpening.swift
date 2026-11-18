#if DEBUG
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation

    /// A system opener that keeps every URL it's handed and opens it, or throws the error it's
    /// told to.
    @MainActor
    final class FakeSystemURLOpening: SystemURLOpening {
        /// What every open throws; nil opens.
        var failure: (any Error)?
        private(set) var opened: [URL] = []

        init(failure: (any Error)? = nil) {
            self.failure = failure
        }

        func open(_ url: URL) async throws {
            opened.append(url)
            if let failure {
                throw failure
            }
        }
    }
#endif
