#if DEBUG
    import Foundation

    /// The thread a URL protocol was started on, and the run loop modes it was running in, where
    /// URL loading expects to hear from the protocol: its client is called there, and its
    /// `stopLoading()` comes there.
    ///
    /// Work performed here runs in the order it was handed over, after whatever the thread is doing,
    /// so a protocol that keeps its state on this thread needs no lock for it.
    struct NetworkClientThread: @unchecked Sendable {
        // `@unchecked`: the thread is only named here, as the target of work any thread may hand
        // it (`perform(_:on:with:waitUntilDone:modes:)` is thread-safe); its state is never read.
        private let thread: Thread
        private let modes: [String]

        /// The thread this is called on, in the mode its run loop is running in, and the default
        /// mode as well: the mode a thread is in when a protocol starts may be one it leaves.
        static var current: Self {
            let mode = RunLoop.current.currentMode ?? .default
            return Self(thread: .current, modes: mode == .default ? [mode.rawValue] : [mode.rawValue, RunLoop.Mode.default.rawValue])
        }

        /// Runs `body` on the thread, after the work handed over before it.
        func perform(_ body: @escaping @Sendable () -> Void) {
            // `perform(_:on:with:waitUntilDone:modes:)` rather than `CFRunLoopPerformBlock`: URL
            // loading's protocol thread runs the sources of its run loop but never the blocks
            // scheduled on it, so a block would wait forever.
            NetworkClientThreadWork(body).perform(#selector(NetworkClientThreadWork.run), on: thread, with: nil, waitUntilDone: false, modes: modes)
        }
    }

    /// A body to run on a thread, in the form `perform(_:on:with:waitUntilDone:modes:)` takes.
    private final class NetworkClientThreadWork: NSObject, Sendable {
        private let body: @Sendable () -> Void

        init(_ body: @escaping @Sendable () -> Void) {
            self.body = body
        }

        @objc func run() {
            body()
        }
    }
#endif
