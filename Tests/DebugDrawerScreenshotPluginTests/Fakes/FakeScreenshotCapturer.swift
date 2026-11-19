#if DEBUG
    @testable import DebugDrawerScreenshotPlugin
    import Foundation

    /// Hands out the captures it is given, in order, without drawing or hiding anything. It records
    /// whether each capture asked to hide the drawer, and, while it holds, keeps a capture waiting
    /// until the test releases it.
    @MainActor
    final class FakeScreenshotCapturer: ScreenshotCapturer {
        /// What each capture returns or throws, first to last.
        private var results: [Result<ScreenshotImage, ScreenshotFailure>]
        /// Whether each capture asked to hide the drawer, in the order asked.
        private(set) var requests: [Bool] = []
        /// Whether a capture waits for ``release()`` before it returns.
        private let holds: Bool
        private var released = false
        private var waiting: CheckedContinuation<Void, Never>?

        init(_ results: [Result<ScreenshotImage, ScreenshotFailure>], holds: Bool = false) {
            self.results = results
            self.holds = holds
        }

        func capture(hidingDrawer: Bool) async throws(ScreenshotFailure) -> ScreenshotImage {
            requests.append(hidingDrawer)
            if holds, !released {
                await withCheckedContinuation { waiting = $0 }
            }
            return try results.removeFirst().get()
        }

        /// Lets the capture held, or the next one, return.
        func release() {
            released = true
            waiting?.resume()
            waiting = nil
        }
    }
#endif
