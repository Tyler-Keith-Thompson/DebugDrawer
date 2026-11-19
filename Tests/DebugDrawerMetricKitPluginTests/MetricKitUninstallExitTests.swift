// Installing subscribes to the payload source of the process that runs it, and the drawer it
// registers with is that process's, so these run in a child process each, in a file of their
// own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    @Suite("MetricKit uninstall, in a child process")
    struct MetricKitUninstallExitTests {
        @Test("Unregistering unsubscribes and an added payload is dropped; installing again subscribes again")
        func unsubscribes() async {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [directory = directory as String] in
                @MainActor
                final class RecordingSource: MetricKitPayloadSource {
                    var receive: (@MainActor ([ReceivedMetricKitPayload]) -> Void)?
                    var subscriptions = 0
                    var unsubscriptions = 0

                    func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
                        subscriptions += 1
                        self.receive = receive
                    }

                    func unsubscribe() {
                        unsubscriptions += 1
                        receive = nil
                    }
                }
                @MainActor func isExpected() -> Bool {
                    let url = URL(filePath: directory, directoryHint: .isDirectory)
                    let source = RecordingSource()
                    MetricKitPayloadsInstallation.install(directory: url, source: source)
                    source.receive?([ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"appVersion":"1.0"}"#.utf8))])

                    DebugDrawer.shared.unregisterGlobal(id: MetricKitPlugin.pluginID)
                    let isListed = DebugDrawer.shared.globalPlugins.contains { $0.id == MetricKitPlugin.pluginID }
                    let unsubscribed = source.receive == nil && source.unsubscriptions == 1
                    MetricKitPayloads.add(json: Data(#"{"appVersion":"2.0"}"#.utf8), kind: .metrics)
                    let keptAfterAdd = MetricKitPayloadStore(directory: url).payloads.count
                    DebugDrawer.shared.unregisterGlobal(id: MetricKitPlugin.pluginID)
                    let unsubscriptionsAfterTwice = source.unsubscriptions
                    MetricKitPayloadsInstallation.install(directory: url, source: nil)

                    return !isListed && unsubscribed && keptAfterAdd == 1 && unsubscriptionsAfterTwice == 1
                        && source.subscriptions == 2 && source.receive != nil
                        && DebugDrawer.shared.badges[MetricKitPlugin.pluginID] == 1
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            try? FileManager.default.removeItem(atPath: directory)
        }

        @Test("In two drawers it stays subscribed until the last removes it, which drops its payloads but not their files")
        func twoDrawers() async {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [directory = directory as String] in
                @MainActor
                final class RecordingSource: MetricKitPayloadSource {
                    var isSubscribed = false

                    func subscribe(_: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
                        isSubscribed = true
                    }

                    func unsubscribe() {
                        isSubscribed = false
                    }
                }
                @MainActor func isExpected() -> Bool {
                    let suite = "MetricKitUninstallExitTests.\(UUID().uuidString)"
                    guard let first = UserDefaults(suiteName: suite + ".first"), let second = UserDefaults(suiteName: suite + ".second") else {
                        return false
                    }
                    let url = URL(filePath: directory, directoryHint: .isDirectory)
                    let source = RecordingSource()
                    // The source is kept from the first install; the shared drawer's plugin is
                    // then removed, so only the two drawers below hold one.
                    MetricKitPayloadsInstallation.install(directory: url.appending(path: "shared"), source: source)
                    DebugDrawer.shared.unregisterGlobal(id: MetricKitPlugin.pluginID)
                    let firstDrawer = DebugDrawer(defaults: first)
                    let secondDrawer = DebugDrawer(defaults: second)
                    let store = MetricKitPayloadStore(directory: url)
                    store.receive([ReceivedMetricKitPayload(kind: .metrics, json: Data(#"{"appVersion":"1.0"}"#.utf8))])
                    let sut = MetricKitPlugin(store: store)

                    firstDrawer.registerGlobal(sut)
                    secondDrawer.registerGlobal(sut)
                    firstDrawer.unregisterGlobal(id: sut.id)
                    let subscribedInSecond = source.isSubscribed
                    let payloadsInSecond = store.payloads.count
                    secondDrawer.unregisterGlobal(id: sut.id)
                    let subscribedAfterLast = source.isSubscribed
                    let payloadsAfterLast = store.payloads.count
                    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
                    firstDrawer.registerGlobal(sut)
                    let payloadsReinstalled = store.payloads.count

                    return subscribedInSecond && payloadsInSecond == 1 && !subscribedAfterLast && payloadsAfterLast == 0
                        && !secondDrawer.globalPlugins.contains { $0.id == sut.id }
                        && files.count { $0.hasSuffix(".json") } == 1
                        && payloadsReinstalled == 1 && source.isSubscribed
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            try? FileManager.default.removeItem(atPath: directory)
        }
    }
#endif
