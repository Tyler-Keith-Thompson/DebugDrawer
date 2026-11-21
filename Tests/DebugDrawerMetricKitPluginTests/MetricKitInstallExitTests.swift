// Installing registers the plugin with the drawer of the process that runs it, and subscribes it
// to MetricKit there, so these run in a child process each, in a file of their own, as exit tests
// need one. The README's example is here, verbatim, rather than in DebugDrawerTests, which links
// core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    import DebugDrawerMetricKit
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    @Suite("MetricKit install, in a child process")
    struct MetricKitInstallExitTests {
        @Test("Install keeps what the source delivers, past payloads first, with a toast and a badge for each new one, kept across launches")
        func install() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [home = home as String, directory = directory as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                /// Delivers one past payload on subscribing, and the next when the test says.
                @MainActor
                final class FakeSource: MetricKitPayloadSource {
                    var receive: (@MainActor ([ReceivedMetricKitPayload]) -> Void)?

                    func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
                        self.receive = receive
                        receive([ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"appVersion":"1.0"}"#.utf8))])
                    }

                    func unsubscribe() {
                        receive = nil
                    }
                }
                let isExpected = await MainActor.run {
                    let url = URL(filePath: directory, directoryHint: .isDirectory)
                    let source = FakeSource()
                    MetricKitPayloadsInstallation.install(directory: url, source: source)
                    let isRegistered = DebugDrawer.shared.globalPlugins.contains { $0.title == "MetricKit" }
                    let firstBadge = DebugDrawer.shared.badges["MetricKitPlugin"]
                    source.receive?([ReceivedMetricKitPayload(kind: .diagnostics, json: Data(#"{"crashDiagnostics":[{}]}"#.utf8))])
                    // Delivered again, as MetricKit's past payloads repeat: nothing new.
                    source.receive?([ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"appVersion":"1.0"}"#.utf8))])
                    let toast = DebugDrawer.shared.toast
                    let relaunched = MetricKitPayloadStore(directory: url).payloads.map(\.kind)
                    return isRegistered && firstBadge == 1 && DebugDrawer.shared.badges["MetricKitPlugin"] == 2
                        && toast?.message == "New MetricKit payload: diagnostics" && toast?.count == 2
                        && relaunched == [.diagnostics, .metrics]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            try? FileManager.default.removeItem(atPath: directory)
        }

        @Test("Installing again registers the plugin once, over the new directory, and keeps one subscriber")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [home = home as String, folder = folder as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                final class CountingSource: MetricKitPayloadSource {
                    var subscriptions = 0

                    func subscribe(_: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
                        subscriptions += 1
                    }

                    func unsubscribe() {}
                }
                let isExpected = await MainActor.run {
                    let first = CountingSource()
                    let second = CountingSource()
                    let other = URL(filePath: folder, directoryHint: .isDirectory).appending(path: "other")
                    MetricKitPayloadsInstallation.install(directory: URL(filePath: folder, directoryHint: .isDirectory), source: first)
                    MetricKitPayloadsInstallation.install(directory: other, source: second)
                    MetricKitPayloads.add(json: Data(#"{"appVersion":"2.0"}"#.utf8), kind: .metrics)
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "MetricKit" }
                    return plugins == 1 && first.subscriptions == 2 && second.subscriptions == 0
                        && MetricKitPayloadStore(directory: other).payloads.count == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            try? FileManager.default.removeItem(atPath: folder)
        }

        @Test("A payload added before install is dropped")
        func addBeforeInstall() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    MetricKitPayloads.add(json: Data("{}".utf8), kind: .metrics)
                    return DebugDrawer.shared.badges["MetricKitPlugin"] == nil
                        && !DebugDrawer.shared.globalPlugins.contains { $0.title == "MetricKit" }
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: MetricKit")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                // The default directory is in Application Support, in the child's temporary home
                // folder (CFFIXED_USER_HOME above).
                let isInstalled = await MainActor.run {
                    // At startup:
                    MetricKitPayloads.install()

                    // A payload from elsewhere, such as one a device exported:
                    let json = Data(#"{"appVersion": "1.2", "cpuMetrics": {}}"#.utf8)
                    MetricKitPayloads.add(json: json, kind: .metrics)

                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "MetricKit" }
                        && DebugDrawer.shared.badges["MetricKitPlugin"] == 1
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
