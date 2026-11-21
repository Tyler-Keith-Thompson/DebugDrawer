// The socket and the app-group store carry a model to another process: here the test process is
// the app, serving Launch Time's real model and the smallest model, and a child process is the
// viewer, as a sidecar app would be. The child exits with success only if every step it waits
// for happens, so each runs as an exit test, in a file of its own.
#if os(macOS) && DEBUG
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

    /// A first frame that never comes in by itself.
    @MainActor
    private final class FakeFirstFrameObserver: FirstFrameObserver {
        func start(_ handler: @escaping @MainActor @Sendable () -> Void) {}
        func stop() {}
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

    @MainActor
    @Suite("Plugin models served to another process", .timeLimit(.minutes(1)))
    struct LaunchTimeTransportExitTests {
        @Test("Over a Unix domain socket, a viewer in another process gets both snapshots, its commands land, and the app's change reaches it")
        func overSocket() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let clock = FakeClock(100.4)
            let launchTime = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 100), firstFrameObserver: FakeFirstFrameObserver())
            let counter = CounterModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(launchTime, id: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin")
            registry.register(counter, id: "Counter")
            let server = DebugDrawerSocketServer(registry: registry, socketPath: "/tmp/dd-\(UUID().uuidString.prefix(8)).sock")
            try server.start()
            clock.now = 100.9
            // The app's own change, made once the viewer's command has landed.
            let answering = Task {
                for await snapshot in counter.$snapshot.values where snapshot.count == 2 {
                    counter.perform(.note("from the app"))
                    return
                }
            }

            await #expect(processExitsWith: .success) { [home = home as String, socketPath = server.socketPath as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func viewerSeesEveryStep() async throws -> Bool {
                    let connection = try DebugDrawerSocketTransport(socketPath: socketPath)
                    let launch = try await connection.connect(
                        toPlugin: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin",
                        snapshot: LaunchTimeSnapshot.self,
                        command: LaunchTimeCommand.self
                    )
                    let counting = try await connection.connect(
                        toPlugin: "Counter",
                        snapshot: CounterModel.Snapshot.self,
                        command: CounterModel.Command.self
                    )
                    let isInitialRight = launch.snapshot == LaunchTimeSnapshot(processStartUptime: 100, appInitUptime: 100.4, firstFrameUptime: nil)
                        && counting.snapshot == CounterModel.Snapshot()
                    launch.send(LaunchTimeCommand(.recordFirstFrame))
                    for await snapshot in launch.snapshots() where snapshot.firstFrameUptime != nil {
                        break
                    }
                    counting.send(.add(2))
                    for await snapshot in counting.snapshots() where snapshot.note == "from the app" {
                        break
                    }
                    return isInitialRight && launch.snapshot.firstFrameUptime == 100.9
                        && counting.snapshot == CounterModel.Snapshot(count: 2, note: "from the app")
                }
                exit(try await viewerSeesEveryStep() ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            #expect(launchTime.snapshot == LaunchTimeSnapshot(processStartUptime: 100, appInitUptime: 100.4, firstFrameUptime: 100.9))
            #expect(counter.snapshot == CounterModel.Snapshot(count: 2, note: "from the app"))
            answering.cancel()
            server.stop()
        }

        @Test("Through the app-group store, a viewer in another process gets both snapshots, its commands land, and the app's change reaches it")
        func throughAppGroupStore() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let clock = FakeClock(100.4)
            let launchTime = LaunchTimeModel(clock: clock, processStart: FakeProcessStart(uptime: 100), firstFrameObserver: FakeFirstFrameObserver())
            let counter = CounterModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(launchTime, id: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin")
            registry.register(counter, id: "Counter")
            let directory = FileManager.default.temporaryDirectory.appending(path: "LaunchTimeTransportExitTests-\(UUID().uuidString)")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            clock.now = 100.9
            // The app's own change, made once the viewer's command has landed.
            let answering = Task {
                for await snapshot in counter.$snapshot.values where snapshot.count == 2 {
                    counter.perform(.note("from the app"))
                    return
                }
            }

            await #expect(processExitsWith: .success) { [home = home as String, path = directory.path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func viewerSeesEveryStep() async throws -> Bool {
                    let store = URL(filePath: path, directoryHint: .isDirectory)
                    let connection = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
                    let launch = try await connection.connect(
                        toPlugin: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin",
                        snapshot: LaunchTimeSnapshot.self,
                        command: LaunchTimeCommand.self
                    )
                    let counting = try await connection.connect(
                        toPlugin: "Counter",
                        snapshot: CounterModel.Snapshot.self,
                        command: CounterModel.Command.self
                    )
                    let isInitialRight = launch.snapshot == LaunchTimeSnapshot(processStartUptime: 100, appInitUptime: 100.4, firstFrameUptime: nil)
                        && counting.snapshot == CounterModel.Snapshot()
                    launch.send(LaunchTimeCommand(.recordFirstFrame))
                    for await snapshot in launch.snapshots() where snapshot.firstFrameUptime != nil {
                        break
                    }
                    counting.send(.add(2))
                    for await snapshot in counting.snapshots() where snapshot.note == "from the app" {
                        break
                    }
                    return isInitialRight && launch.snapshot.firstFrameUptime == 100.9
                        && counting.snapshot == CounterModel.Snapshot(count: 2, note: "from the app")
                }
                exit(try await viewerSeesEveryStep() ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            #expect(launchTime.snapshot == LaunchTimeSnapshot(processStartUptime: 100, appInitUptime: 100.4, firstFrameUptime: 100.9))
            #expect(counter.snapshot == CounterModel.Snapshot(count: 2, note: "from the app"))
            answering.cancel()
            server.stop()
        }
    }
#endif
