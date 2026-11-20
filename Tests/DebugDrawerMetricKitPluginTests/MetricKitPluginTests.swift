#if DEBUG
    import DebugDrawer
    import DebugDrawerMetricKit
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct MetricKitPluginTests {
        @Test("The plugin is MetricKit, in the Performance category, and adds to bug reports")
        func identity() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }

            let sut = MetricKitPlugin(store: MetricKitPayloadStore(directory: directory))

            #expect(sut.id == "MetricKitPlugin")
            #expect(sut.title == "MetricKit")
            #expect(sut.category == "Performance")
            #expect(sut.icon == "chart.bar.doc.horizontal")
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The drawer's search offers deleting every payload, found by \"metrics\" too")
        func action() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = MetricKitPayloadStore(directory: directory)
            store.receive([ReceivedMetricKitPayload(kind: .metrics, json: Data("{}".utf8))])
            let sut = MetricKitPlugin(store: store)

            let actual = try #require(sut.actions.first)
            actual.perform()

            #expect(sut.actions.map(\.title) == ["Delete MetricKit payloads"])
            #expect(actual.keywords.contains("metrics"))
            #expect(store.payloads.isEmpty)
        }

        @Test("The bug report gets each payload as formatted JSON named by its kind and the end of its period")
        func report() throws {
            let payloads = [
                MetricKitPayload(
                    id: UUID(), kind: .diagnostics, begin: Date(timeIntervalSince1970: 1_763_290_000),
                    end: Date(timeIntervalSince1970: 1_763_290_000), received: Date(timeIntervalSince1970: 1_763_290_000),
                    json: Data(#"{"crashDiagnostics":[]}"#.utf8), isSeen: false
                ),
                MetricKitPayload(
                    id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86400),
                    received: Date(timeIntervalSince1970: 86400), json: Data(#"{"appVersion":"1.0"}"#.utf8), isSeen: true
                )
            ]
            let expectedNames = ["diagnostics 2025-11-16T10-46-40Z.json", "metrics 1970-01-02T00-00-00Z.json"]
            let expectedJSON = "{\n  \"crashDiagnostics\" : [\n\n  ]\n}"
            var actual = DebugDrawerReport()

            MetricKitPlugin.contribute(payloads, to: &actual)

            #expect(actual.files.map(\.name) == expectedNames)
            #expect(actual.files.map(\.kind) == [.json, .json])
            #expect(String(bytes: try #require(actual.files.first).data, encoding: .utf8) == expectedJSON)
        }

        @Test("No payloads add nothing to the bug report")
        func reportEmpty() {
            var actual = DebugDrawerReport()

            MetricKitPlugin.contribute([], to: &actual)

            #expect(actual.files.isEmpty)
        }

        @Test("The default directory is the app's own folder in Application Support")
        func defaultDirectory() {
            let actual = MetricKitPayloads.defaultDirectory

            #expect(actual.lastPathComponent == "DebugDrawer MetricKit Payloads")
            #expect(actual.deletingLastPathComponent().deletingLastPathComponent() == URL.applicationSupportDirectory)
        }
    }
#endif
