#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerLaunchTimePlugin
    import Foundation
    import Testing

    /// A clock the test moves by hand.
    private final class FakeClock: UptimeClock {
        var now: TimeInterval
        init(_ now: TimeInterval) { self.now = now }
        var uptime: TimeInterval { now }
    }

    /// A process that started at `uptime`.
    private struct FakeProcessStart: ProcessStartReader {
        let uptime: TimeInterval?
        func processStartUptime() -> TimeInterval? { uptime }
    }

    /// A first frame the test brings in by hand.
    @MainActor
    private final class FakeFirstFrameObserver: FirstFrameObserver {
        private var handler: (@MainActor @Sendable () -> Void)?

        func start(_ handler: @escaping @MainActor @Sendable () -> Void) {
            self.handler = handler
        }

        func stop() {
            handler = nil
        }

        func bringInFirstFrame() {
            handler?()
        }
    }

    /// The smallest model: a count and a note.
    @MainActor
    private final class CounterModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
            var note = ""
        }

        enum Command: Codable, Sendable {
            case add(Int)
            case note(String)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .add(amount): snapshot.count += amount
            case let .note(text): snapshot.note = text
            }
        }
    }

    /// Each way a viewer reaches the app's models.
    private enum TransportKind: String, CaseIterable, Sendable {
        case inProcess
        case socket
        case appGroupStore
    }

    /// A viewer's connection, and the servers it runs over, which stop with it.
    @MainActor
    private struct Connection {
        let transport: any DebugDrawerTransport
        let stop: @MainActor () -> Void
    }

    extension TransportKind {
        /// Serves `registry` over this kind of transport and connects a viewer to it: the one
        /// place the tests below name a transport.
        @MainActor
        fileprivate func connect(to registry: DebugDrawerModelRegistry) throws -> Connection {
            switch self {
            case .inProcess:
                return Connection(transport: DebugDrawerInProcessTransport(registry: registry)) {}
            case .socket:
                let server = DebugDrawerSocketServer(registry: registry, socketPath: "/tmp/dd-\(UUID().uuidString.prefix(8)).sock")
                try server.start()
                return try Connection(transport: DebugDrawerSocketTransport(socketPath: server.socketPath)) { server.stop() }
            case .appGroupStore:
                let directory = FileManager.default.temporaryDirectory.appending(path: "LaunchTimeTransportTests-\(UUID().uuidString)")
                let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
                try server.start()
                return try Connection(transport: DebugDrawerAppGroupStoreTransport(directory: server.appDirectory)) { server.stop() }
            }
        }
    }

    // The same scenario over every transport, with Launch Time's real model (its clock, process
    // start and first frame faked) and the smallest model there is: the snapshot arrives, a
    // command sent lands in the model, and a change made in the app reaches the viewer. Neither
    // model, nor the view code that would draw the transport, knows which transport it is on. Each
    // wait is for the snapshot the step should produce, so nothing waits on time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LaunchTimeTransportTests {
        @Test(
            "Launch Time's snapshot arrives, and Record First Frame sent from the viewer lands and comes back",
            arguments: TransportKind.allCases
        )
        fileprivate func launchTimeCommandRoundTrip(kind: TransportKind) async throws {
            let clock = FakeClock(100.4)
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 100), firstFrameObserver: FakeFirstFrameObserver())
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin")
            let connection = try kind.connect(to: registry)
            let expectedInitial = LaunchTimeSnapshot(processStartUptime: 100, appInitUptime: 100.4, firstFrameUptime: nil)
            let expected = LaunchTimeSnapshot(processStartUptime: 100, appInitUptime: 100.4, firstFrameUptime: 100.9)

            let sut = try await connection.transport.connect(
                toPlugin: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin",
                snapshot: LaunchTimeSnapshot.self,
                command: LaunchTimeCommand.self
            )
            let initial = sut.snapshot
            clock.now = 100.9
            sut.send(LaunchTimeCommand(.recordFirstFrame))
            for await snapshot in sut.snapshots() where snapshot.firstFrameUptime != nil {
                break
            }

            #expect(initial == expectedInitial)
            #expect(model.snapshot == expected)
            #expect(sut.snapshot == expected)
            connection.stop()
        }

        @Test("A first frame Launch Time's model records in the app reaches the viewer", arguments: TransportKind.allCases)
        fileprivate func launchTimeChangePropagates(kind: TransportKind) async throws {
            let clock = FakeClock(50)
            let firstFrame = FakeFirstFrameObserver()
            let model = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 49.5), firstFrameObserver: firstFrame)
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin")
            let connection = try kind.connect(to: registry)
            let expected = LaunchTimeSnapshot(processStartUptime: 49.5, appInitUptime: 50, firstFrameUptime: 50.25)
            let sut = try await connection.transport.connect(
                toPlugin: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin",
                snapshot: LaunchTimeSnapshot.self,
                command: LaunchTimeCommand.self
            )

            model.waitForFirstFrame()
            clock.now = 50.25
            firstFrame.bringInFirstFrame()
            for await snapshot in sut.snapshots() where snapshot.firstFrameUptime != nil {
                break
            }

            #expect(sut.snapshot == expected)
            connection.stop()
        }

        @Test(
            "The smallest model's snapshot arrives, a command lands, and a change made in the app reaches the viewer",
            arguments: TransportKind.allCases
        )
        fileprivate func counterScenario(kind: TransportKind) async throws {
            let model = CounterModel()
            model.perform(.add(1))
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Counter")
            let connection = try kind.connect(to: registry)
            let expectedAfterCommand = CounterModel.Snapshot(count: 3)
            let expected = CounterModel.Snapshot(count: 3, note: "from the app")

            let sut = try await connection.transport.connect(
                toPlugin: "Counter",
                snapshot: CounterModel.Snapshot.self,
                command: CounterModel.Command.self
            )
            let initial = sut.snapshot
            sut.send(.add(2))
            for await snapshot in sut.snapshots() where snapshot == expectedAfterCommand {
                break
            }
            let afterCommand = model.snapshot
            model.perform(.note("from the app"))
            for await snapshot in sut.snapshots() where snapshot == expected {
                break
            }

            #expect(initial == CounterModel.Snapshot(count: 1))
            #expect(afterCommand == expectedAfterCommand)
            #expect(sut.snapshot == expected)
            connection.stop()
        }
    }
#endif
