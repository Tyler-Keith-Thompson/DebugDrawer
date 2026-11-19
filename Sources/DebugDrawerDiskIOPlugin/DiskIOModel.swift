import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The model composes the event source rather than replacing the store: the store keeps the
    // recording it runs for the process, fed by the swizzled methods and the interposer on any
    // thread, and its public API (`filterOp`, `capacity`, `$events`) keeps working; the model is
    // the one way in for a view. The recording path is untouched: the model reads the store's
    // list and totals on the main actor, as the view did.
    //
    // Every command but a volume read is synchronous, so it lands before `perform(_:)` returns, in
    // the order sent, and the picker and switch bound through a direct transport read back what
    // was set. A volume read waits on the disk off the main actor; each one waits for the one sent
    // before it, so the volumes land in the order they were asked for and the last one stays.

    /// The Disk I/O plugin's state and behavior, without its views: the recorded calls and their
    /// totals, the filter, whether recording is paused, and the volume's size and free space, read
    /// as a ``DiskIOSnapshot`` and changed with a ``DiskIOCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: DiskIOModel.shared)
    /// ```
    ///
    /// Recording starts and stops with the plugin's ``DiskIOPlugin/install(in:)`` and
    /// ``DiskIOPlugin/uninstall(from:)``, as it does without the model. Release builds get a
    /// stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class DiskIOModel: DebugDrawerPluginModel {
        /// The model over the store `installDiskIO()` fills, which the plugin shows.
        public static let shared = DiskIOModel(source: DiskIOStore.shared, volumes: _DiskSpaceReading())

        // The source's own publisher, handed out as the model's: a delivery of recorded calls then
        // announces itself once, to whoever watches, and costs nothing more while nothing does. A
        // sink forwarding it to a publisher of the model's own added mallocs to every recorded
        // call the main queue delivered on its own (the Disk I/O benchmark's gate). Set once in
        // `init` and never changed, so reading it from any isolation is safe.
        public nonisolated(unsafe) let objectWillChange: ObservableObjectPublisher

        /// The home directory's volume, as last read; announced through the source's publisher.
        private var volume: DiskSpace? {
            willSet { objectWillChange.send() }
        }

        private let source: any DiskIOEventSource
        private let volumes: any DiskSpaceReading
        /// The last volume read asked for; the next one waits for it.
        private var volumeRead: Task<Void, Never>?
        /// The drawers the plugin is installed in; recording runs while there is one.
        private var installations: Set<ObjectIdentifier> = []

        /// - Parameters:
        ///   - source: The recorded calls, their totals and the switches for recording.
        ///   - volumes: Reads the volume's size and free space.
        init(source: any DiskIOEventSource, volumes: any DiskSpaceReading) {
            self.source = source
            self.volumes = volumes
            objectWillChange = source.objectWillChange
        }

        public var snapshot: DiskIOSnapshot {
            DiskIOSnapshot(
                events: source.events,
                totals: source.totals,
                operation: source.filterOp,
                mainThreadOnly: source.mainThreadOnly,
                isPaused: source.isPaused,
                volume: volume
            )
        }

        public func perform(_ command: DiskIOCommand) {
            switch command.action {
            case let .setOperation(operation): source.filterOp = operation
            case let .setMainThreadOnly(mainThreadOnly): source.mainThreadOnly = mainThreadOnly
            case .clear: source.clear()
            case let .setPaused(paused): source.setPaused(paused)
            case .refreshVolume: readVolume()
            }
        }

        /// Counts `drawer` as one the plugin is installed in, and starts recording; starting again
        /// while recording does nothing.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
            source.startRecording()
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, stops recording and forgets the
        /// calls. The filter stays.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            source.stopRecording()
        }

        /// Reads the volume once the read asked for before this one has landed.
        private func readVolume() {
            let previous = volumeRead
            volumeRead = Task {
                await previous?.value
                volume = await volumes.read()
            }
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds record no disk I/O: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class DiskIOModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = DiskIOModel()

        /// Never sends: nothing changes.
        public nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

        private init() {}

        /// Always empty.
        public var snapshot: DiskIOSnapshot {
            DiskIOSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: DiskIOCommand) {}
    }
#endif
