import Combine

// What a model-backed plugin's view draws from. The view sees the latest snapshot synchronously
// (`snapshot`, so its first frame is complete and a binding reads back what it just set) and
// re-renders on `objectWillChange`; `snapshots()` hands the same changes out as a stream of values,
// which is what crosses to another process. Rejected: a view that iterates an `AsyncStream` into
// `@State` (its first frame is empty, and every change lands a hop late) and a protocol with one
// conformer per transport (a view would be generic over it for no gain; the two ways in are
// initializers of one type).

#if DEBUG
    /// Joins a plugin's view to its model: the latest ``snapshot`` to draw, and ``send(_:)`` for
    /// what the view asks.
    ///
    /// ``direct(to:)`` joins them in the process: the snapshot is the model's own, and a command
    /// runs at once. ``init(initial:snapshots:send:)`` takes the snapshots from a stream and hands
    /// the commands to a closure, for a model that lives elsewhere. Either way the view observes the
    /// transport, so it draws each new snapshot, and never touches the model.
    ///
    /// ```swift
    /// struct CounterView: View {
    ///     @StateObject private var transport: DebugDrawerPluginTransport<CounterModel.Snapshot, CounterModel.Command>
    ///
    ///     init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<CounterModel.Snapshot, CounterModel.Command>) {
    ///         _transport = StateObject(wrappedValue: transport())
    ///     }
    ///
    ///     var body: some View {
    ///         DebugDrawerKeyValueRow("Count", value: "\(transport.snapshot.count)")
    ///         Button("Add One") { transport.send(.increment) }
    ///     }
    /// }
    /// ```
    ///
    /// Release builds get a stand-in that keeps the first snapshot it is given and drops every
    /// command.
    @MainActor
    public final class DebugDrawerPluginTransport<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>: ObservableObject {
        /// Where the snapshot comes from: a model in this process, read each time, or the last one a
        /// stream delivered.
        private enum Source {
            case model(@MainActor () -> Snapshot)
            case received(Snapshot)
        }

        private var source: Source
        private let deliver: @MainActor (Command) -> Void
        /// Forwards the model's changes, for a direct transport.
        private var modelChanges: AnyCancellable?
        /// Reads the stream of snapshots, for a streamed transport; cancelled with the transport.
        private var receiving: Task<Void, Never>?

        private init(source: Source, deliver: @escaping @MainActor (Command) -> Void) {
            self.source = source
            self.deliver = deliver
        }

        /// A transport to `model`, in this process: ``snapshot`` is the model's, read as the view
        /// draws, and ``send(_:)`` performs the command at once.
        ///
        /// - Parameter model: The plugin's model.
        /// - Returns: A transport that holds `model` while it lives.
        public static func direct<Model: DebugDrawerPluginModel>(to model: Model) -> DebugDrawerPluginTransport
            where Model.Snapshot == Snapshot, Model.Command == Command {
            let transport = DebugDrawerPluginTransport(source: .model { model.snapshot }) { model.perform($0) }
            transport.modelChanges = model.objectWillChange.sink { [weak transport] _ in
                transport?.objectWillChange.send()
            }
            return transport
        }

        /// A transport that shows the snapshots `snapshots` delivers, starting from `initial`, and
        /// hands each command to `send`: for a model that lives elsewhere, behind a connection that
        /// decodes its snapshots and encodes its commands.
        ///
        /// - Parameters:
        ///   - initial: What to show until the stream delivers a snapshot.
        ///   - snapshots: The model's snapshots, each shown as it arrives; read until it finishes or
        ///     the transport goes.
        ///   - send: Carries a command to the model.
        public init(initial: Snapshot, snapshots: AsyncStream<Snapshot>, send: @escaping @MainActor (Command) -> Void) {
            source = .received(initial)
            deliver = send
            receiving = Task { [weak self] in
                for await snapshot in snapshots {
                    guard let self else { return }
                    objectWillChange.send()
                    source = .received(snapshot)
                }
            }
        }

        deinit {
            receiving?.cancel()
        }

        /// The model's state as the view should draw it now.
        public var snapshot: Snapshot {
            switch source {
            case let .model(read): read()
            case let .received(snapshot): snapshot
            }
        }

        /// Asks the model to do `command`. A direct transport performs it before returning.
        ///
        /// - Parameter command: What to do.
        public func send(_ command: Command) {
            deliver(command)
        }

        /// The current snapshot, then one after each change, for as long as the stream is read: what
        /// a connection to another process forwards. Changes that land while the reader is busy are
        /// folded into the next snapshot it gets.
        ///
        /// - Returns: A stream for one reader.
        public func snapshots() -> AsyncStream<Snapshot> {
            AsyncStream { continuation in
                // A change is announced before it lands, and the reader resumes on the main actor
                // only after the code making it has returned, so the snapshot it reads holds it.
                let forwarding = Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.finish()
                        return
                    }
                    let (changes, change) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                    let subscription = objectWillChange.sink { change.yield() }
                    continuation.yield(snapshot)
                    for await _ in changes {
                        continuation.yield(snapshot)
                    }
                    subscription.cancel()
                    continuation.finish()
                }
                continuation.onTermination = { _ in forwarding.cancel() }
            }
        }
    }
#else
    // The release stand-in: the same members, holding the first snapshot it is given and dropping
    // every command.

    /// Release builds have no drawer: this stand-in keeps the first snapshot it is given and drops
    /// every command.
    @MainActor
    public final class DebugDrawerPluginTransport<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>: ObservableObject {
        /// The snapshot the transport was made with.
        public let snapshot: Snapshot

        private init(snapshot: Snapshot) {
            self.snapshot = snapshot
        }

        /// A transport holding `model`'s snapshot as it is now.
        ///
        /// - Parameter model: The plugin's model.
        /// - Returns: A transport that never changes.
        public static func direct<Model: DebugDrawerPluginModel>(to model: Model) -> DebugDrawerPluginTransport
            where Model.Snapshot == Snapshot, Model.Command == Command {
            DebugDrawerPluginTransport(snapshot: model.snapshot)
        }

        /// A transport holding `initial`; the stream isn't read.
        ///
        /// - Parameters:
        ///   - initial: The snapshot it holds.
        ///   - snapshots: Ignored.
        ///   - send: Ignored.
        public init(initial: Snapshot, snapshots: AsyncStream<Snapshot>, send: @escaping @MainActor (Command) -> Void) {
            snapshot = initial
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func send(_ command: Command) {}

        /// The one snapshot the transport holds, then the end.
        ///
        /// - Returns: A stream of one snapshot.
        public func snapshots() -> AsyncStream<Snapshot> {
            AsyncStream { continuation in
                continuation.yield(snapshot)
                continuation.finish()
            }
        }
    }
#endif
