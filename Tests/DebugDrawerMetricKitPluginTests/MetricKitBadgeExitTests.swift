// Installing the plugin on any drawer subscribes to the payload source of the process that runs
// it, and the shared drawer is that process's, so these run in a child process each, in a file of
// their own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    import DebugDrawerMetricKit
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    @Suite("MetricKit badges, in a child process", .timeLimit(.minutes(1)))
    struct MetricKitBadgeExitTests {
        @Test("Installed only in a drawer of its own, the plugin badges that drawer as its unseen payloads change, and never the shared one")
        func badgesItsOwnDrawer() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [home = home as String, directory = directory as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                /// Delivers nothing on its own: the test hands the store its payloads.
                @MainActor
                final class SilentSource: MetricKitPayloadSource {
                    func subscribe(_: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {}
                    func unsubscribe() {}
                }
                @MainActor func isExpected() -> Bool {
                    func payload(_ version: String) -> [ReceivedMetricKitPayload] {
                        [ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"appVersion":"\#(version)"}"#.utf8))]
                    }
                    let suite = "MetricKitBadgeExitTests.badgesItsOwnDrawer.\(UUID().uuidString)"
                    guard let defaults = UserDefaults(suiteName: suite) else { return false }
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let url = URL(filePath: directory, directoryHint: .isDirectory)
                    // The source is kept from the first install, so the drawer below doesn't
                    // subscribe to MetricKit itself; the shared drawer's plugin is then removed, so
                    // only that drawer holds one.
                    MetricKitPayloadsInstallation.install(directory: url.appending(path: "shared"), source: SilentSource())
                    DebugDrawer.shared.unregisterGlobal(id: MetricKitPlugin.pluginID)
                    let store = MetricKitPayloadStore(directory: url.appending(path: "own"))
                    let sut = MetricKitPlugin(store: store)
                    _ = store.receive(payload("1.0"))
                    let beforeInstall = [drawer.badges[sut.id], DebugDrawer.shared.badges[sut.id]]

                    drawer.registerGlobal(sut)
                    let installed = drawer.badges[sut.id]
                    _ = store.receive(payload("1.1"))
                    let added = drawer.badges[sut.id]
                    store.markAllSeen()
                    let seen = drawer.badges[sut.id]
                    _ = store.receive(payload("1.2"))
                    let sharedWhileInstalled = DebugDrawer.shared.badges[sut.id]
                    drawer.unregisterGlobal(id: sut.id)
                    let removed = drawer.badges[sut.id]
                    _ = store.receive(payload("1.3"))

                    return beforeInstall == [nil, nil] && installed == 1 && added == 2 && seen == nil
                        && sharedWhileInstalled == nil && removed == nil
                        && drawer.badges[sut.id] == nil && DebugDrawer.shared.badges[sut.id] == nil
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            try? FileManager.default.removeItem(atPath: directory)
        }
    }
#endif
