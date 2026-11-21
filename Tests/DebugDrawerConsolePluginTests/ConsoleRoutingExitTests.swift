// Exit tests start a child process, which only the Mac's test runs can do. Installing the console
// redirects the process's stdout and stderr and registers an os_log driver with OSLogClient, which
// is set up once a process, so it happens only in a child.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import DebugDrawerTestSupport
    import Foundation
    import OSLogClient
    import Testing

    @Suite("Console capture goes to the drawer that installed the plugin last, in a child process", .timeLimit(.minutes(1)))
    struct ConsoleRoutingExitTests {
        @Test("""
        Installed on a drawer of its own, the plugin's store gets stdout, the sink and os_log, and the shared store none; once removed, \
        the shared drawer's plugin captures again
        """)
        func latestInstallGetsTheLines() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func waitForLine(_ text: String, in store: ConsoleLogStore) async {
                    for await lines in store.$lines.values where lines.contains(where: { $0.text == text }) {
                        return
                    }
                }

                /// Hands the console's os_log driver an entry, as OSLogClient does as it reads one.
                func logThroughDriver(_ message: String) {
                    ConsoleCapture.driver.processLog(
                        level: .notice, subsystem: "com.example.routing", category: "test", date: Date(), message: message, components: []
                    )
                }

                @MainActor
                func route() async throws {
                    let suite = temporarySuiteName("ConsoleRoutingExitTests")
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let shared = ConsoleLogStore.shared
                    let store = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
                    let plugin = ConsolePlugin(model: ConsoleModel(store: store, sessions: ConsoleSessionsModel()))
                    let drawer = DebugDrawer(defaults: defaults)
                    // The app's drawer holds the plugin first, as an app installs it at launch. Its
                    // plugin is registered as installConsole() registers it, with no session
                    // recorder, which could delete the sessions other children write.
                    DebugDrawer.shared.registerGlobal(ConsolePlugin())

                    drawer.registerGlobal(plugin)
                    FileHandle.standardOutput.write(Data("Own stdout\n".utf8))
                    ConsoleLogSink.log(level: .info, message: "Own sink")
                    logThroughDriver("Own os_log")
                    await waitForLine("Own stdout", in: store)
                    await waitForLine("Own sink", in: store)
                    await waitForLine("Own os_log", in: store)
                    let ownTexts = Set(store.lines.map(\.text))
                    let sharedWhileInstalled = shared.lines.map(\.text)
                    drawer.unregisterGlobal(id: plugin.id)
                    FileHandle.standardOutput.write(Data("Shared stdout\n".utf8))
                    ConsoleLogSink.log(level: .info, message: "Shared sink")
                    logThroughDriver("Shared os_log")
                    await waitForLine("Shared stdout", in: shared)
                    await waitForLine("Shared sink", in: shared)
                    await waitForLine("Shared os_log", in: shared)
                    let sharedTexts = shared.lines.map(\.text)

                    #expect(ownTexts.isSuperset(of: ["Own stdout", "Own sink", "Own os_log"]))
                    #expect(!sharedWhileInstalled.contains { $0.hasPrefix("Own") })
                    #expect(store.lines.isEmpty)
                    #expect(store.capture == .stopped)
                    #expect(shared.capture == .running)
                    #expect(!sharedTexts.contains { $0.hasPrefix("Own") })
                }
                try await route()
            }
        }

        @Test("""
        Two drawers of their own: the later one's store captures, and the earlier one's again once the later removes the plugin; the \
        last removal stops capture
        """)
        func twoDrawersOfTheirOwn() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func waitForLine(_ text: String, in store: ConsoleLogStore) async {
                    for await lines in store.$lines.values where lines.contains(where: { $0.text == text }) {
                        return
                    }
                }

                @MainActor
                func route() async throws {
                    let suite = temporarySuiteName("ConsoleRoutingExitTests")
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let firstStore = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
                    let secondStore = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
                    let firstPlugin = ConsolePlugin(model: ConsoleModel(store: firstStore, sessions: ConsoleSessionsModel()))
                    let secondPlugin = ConsolePlugin(model: ConsoleModel(store: secondStore, sessions: ConsoleSessionsModel()))
                    let first = DebugDrawer(defaults: defaults)
                    let second = DebugDrawer(defaults: defaults)

                    first.registerGlobal(firstPlugin)
                    second.registerGlobal(secondPlugin)
                    ConsoleLogSink.log(level: .info, message: "To the second")
                    await waitForLine("To the second", in: secondStore)
                    let firstWhileSecond = firstStore.lines.map(\.text)
                    second.unregisterGlobal(id: secondPlugin.id)
                    ConsoleLogSink.log(level: .info, message: "To the first")
                    await waitForLine("To the first", in: firstStore)
                    let isRunningWithOneLeft = ConsoleCapture.isRunning
                    first.unregisterGlobal(id: firstPlugin.id)

                    #expect(!firstWhileSecond.contains("To the second"))
                    #expect(secondStore.lines.isEmpty)
                    #expect(secondStore.capture == .stopped)
                    #expect(isRunningWithOneLeft)
                    #expect(!ConsoleCapture.isRunning)
                    #expect(firstStore.capture == .stopped)
                    #expect(ConsoleLogStore.shared.lines.isEmpty)
                }
                try await route()
            }
        }
    }
#endif
