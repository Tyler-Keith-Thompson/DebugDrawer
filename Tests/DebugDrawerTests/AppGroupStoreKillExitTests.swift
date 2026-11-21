// The app-group store between two processes that come and go: a child process is the app or the
// viewer, and the test process the other. A child that must die mid-write lowers its file size
// limit (RLIMIT_FSIZE) first, so the kernel kills it with SIGXFSZ inside the write that crosses it:
// part-way through, every time, with no hook in the code under test and no race to win.
#if os(macOS) && DEBUG
    import Combine
    @testable import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A model whose snapshot is a tally and a note, changed by commands.
    @MainActor
    private final class TallyModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
            var note = ""
        }

        enum Command: Codable, Equatable, Sendable {
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
    @Suite("The app-group store across processes that quit or are killed", .timeLimit(.minutes(1)))
    struct AppGroupStoreKillExitTests {
        @Test("Snapshots an app wrote while no viewer ran, then quit, are read by a viewer that launches after it")
        func viewerLaunchesAfterTheApp() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreKillExitTests-\(UUID().uuidString)")
            let expected = TallyModel.Snapshot(count: 3, note: "written alone")

            await #expect(processExitsWith: .success) { [home = home as String, path = directory.path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func writeAndQuit() async -> Bool {
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: URL(filePath: path)))
                    let model = TallyModel()
                    let registry = DebugDrawerModelRegistry()
                    registry.register(model, id: "Tally")
                    let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: URL(filePath: path))
                    guard (try? server.start()) != nil, let watcher = DirectoryWatcher(directory: layout.snapshots) else { return false }
                    model.perform(.add(3))
                    model.perform(.note("written alone"))
                    let expected = TallyModel.Snapshot(count: 3, note: "written alone")
                    func isWritten() -> Bool {
                        guard let data = try? Data(contentsOf: layout.snapshotFile(for: "Tally")),
                              let document = StoreDocument.decoded(from: data) else { return false }
                        return (try? JSONDecoder().decode(TallyModel.Snapshot.self, from: document.message.payload)) == expected
                    }
                    if isWritten() { return true }
                    for await _ in watcher.changes where isWritten() {
                        return true
                    }
                    return false
                }
                exit(await writeAndQuit() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
            let sut = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let actual = try await sut.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)

            #expect(actual.snapshot == expected)
        }

        @Test("An app killed while writing a snapshot leaves the last complete one for the viewer, and the cut-off file is never read")
        func appKilledMidWrite() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreKillExitTests-\(UUID().uuidString)")
            let snapshots = AppGroupStoreLayout.appDirectory(inStore: directory).appending(path: "snapshots")
            let expected = TallyModel.Snapshot(note: "last complete")

            await #expect(processExitsWith: .signal(SIGXFSZ)) { [home = home as String, path = directory.path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                @MainActor
                func writeUntilKilled() async {
                    let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: URL(filePath: path)))
                    let model = TallyModel()
                    let registry = DebugDrawerModelRegistry()
                    registry.register(model, id: "Tally")
                    let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: URL(filePath: path))
                    guard (try? server.start()) != nil, let watcher = DirectoryWatcher(directory: layout.snapshots) else { return }
                    func holds(_ snapshot: TallyModel.Snapshot) -> Bool {
                        guard let data = try? Data(contentsOf: layout.snapshotFile(for: "Tally")),
                              let document = StoreDocument.decoded(from: data) else { return false }
                        return (try? JSONDecoder().decode(TallyModel.Snapshot.self, from: document.message.payload)) == snapshot
                    }
                    let complete = TallyModel.Snapshot(note: "last complete")
                    let large = TallyModel.Snapshot(note: String(repeating: "x", count: 1 << 20))
                    model.perform(.note(complete.note))
                    if !holds(complete) {
                        for await _ in watcher.changes where holds(complete) {
                            break
                        }
                    }
                    // Output to /dev/null, as the test's log may already be past the limit and a
                    // line written there would end the child first; no core file; then a size
                    // limit far below the next snapshot's.
                    let null = open("/dev/null", O_WRONLY)
                    dup2(null, STDOUT_FILENO)
                    dup2(null, STDERR_FILENO)
                    var core = rlimit(rlim_cur: 0, rlim_max: 0)
                    setrlimit(RLIMIT_CORE, &core)
                    var size = rlimit()
                    getrlimit(RLIMIT_FSIZE, &size)
                    size.rlim_cur = 64 << 10
                    setrlimit(RLIMIT_FSIZE, &size)
                    model.perform(.note(large.note))
                    // The server writes it on the main actor once this waits, and the write kills
                    // the process. Should it survive, the file lands and the child exits with
                    // success, which fails the test.
                    for await _ in watcher.changes where holds(large) {
                        return
                    }
                }
                await writeUntilKilled()
                exit(EXIT_SUCCESS)
            }
            let names = try FileManager.default.contentsOfDirectory(atPath: snapshots.path).sorted()
            let cutOffName = try #require(names.first { $0 != "Tally.json" })
            let cutOff = try Data(contentsOf: snapshots.appending(path: cutOffName))
            let sut = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let actual = try await sut.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)

            #expect(names.count == 2)
            #expect((1..<(1 << 20)).contains(cutOff.count))
            #expect(StoreDocument.decoded(from: cutOff) == nil)
            #expect(actual.snapshot == expected)
        }

        @Test("A viewer killed while leaving a command leaves the app the commands before it, and the cut-off file is never performed")
        func viewerKilledMidWrite() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppGroupStoreKillExitTests-\(UUID().uuidString)")
            let commands = AppGroupStoreLayout.appDirectory(inStore: directory).appending(path: "commands")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let reading = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            _ = try await reading.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            // The app is suspended while the viewer runs.
            server.stop()
            let expected = TallyModel.Snapshot(note: "last complete")

            await #expect(processExitsWith: .signal(SIGXFSZ)) { [home = home as String, path = directory.path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                @MainActor
                func sendUntilKilled() async throws {
                    let connection = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: URL(filePath: path)))
                    let viewer = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
                    viewer.send(.note("last complete"))
                    // Output to /dev/null, no core file, then a size limit far below the next
                    // command's.
                    let null = open("/dev/null", O_WRONLY)
                    dup2(null, STDOUT_FILENO)
                    dup2(null, STDERR_FILENO)
                    var core = rlimit(rlim_cur: 0, rlim_max: 0)
                    setrlimit(RLIMIT_CORE, &core)
                    var size = rlimit()
                    getrlimit(RLIMIT_FSIZE, &size)
                    size.rlim_cur = 64 << 10
                    setrlimit(RLIMIT_FSIZE, &size)
                    // Written before send returns: the write kills the process.
                    viewer.send(.note(String(repeating: "x", count: 1 << 20)))
                }
                try? await sendUntilKilled()
                exit(EXIT_SUCCESS)
            }
            let left = try FileManager.default.contentsOfDirectory(atPath: commands.path).sorted()
            let cutOffName = try #require(left.first { !$0.hasSuffix(".json") })
            let cutOff = try Data(contentsOf: commands.appending(path: cutOffName))
            try server.start()
            for await snapshot in model.$snapshot.values where !snapshot.note.isEmpty {
                break
            }
            let remaining = try FileManager.default.contentsOfDirectory(atPath: commands.path)

            #expect(left.count == 2)
            #expect(StoreDocument.decoded(from: cutOff) == nil)
            #expect(model.snapshot == expected)
            #expect(remaining == [cutOffName])
            server.stop()
        }
    }
#endif
