import Combine

#if DEBUG
    /// Where the Disk I/O model's calls come from: the recorded calls and their totals, the list's
    /// filter, and the switches that start, stop and pause recording.
    ///
    /// ``DiskIOStore`` is the real one, filled by the swizzled methods; a test passes one of its
    /// own. It announces each change through `objectWillChange`, before the change lands, as the
    /// store's `@Published` properties do.
    @MainActor
    protocol DiskIOEventSource: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
        /// The kept calls, newest first.
        var events: [IOEvent] { get }
        /// Every call since the last clear, including the ones ``events`` no longer keeps.
        var totals: DiskIOTotals { get }
        /// The operation the list shows alone, or `nil` for every operation.
        var filterOp: IOEvent.Operation? { get set }
        /// Whether the list shows only the calls made on the main thread.
        var mainThreadOnly: Bool { get set }
        /// Whether recording is paused.
        var isPaused: Bool { get }

        /// Starts recording, as the first drawer installs the plugin.
        func startRecording()
        /// Stops recording and forgets the calls, as the last drawer removes the plugin.
        func stopRecording()
        /// Pauses recording, or resumes it.
        func setPaused(_ paused: Bool)
        /// Forgets the kept calls and starts the totals over.
        func clear()
    }
#endif
