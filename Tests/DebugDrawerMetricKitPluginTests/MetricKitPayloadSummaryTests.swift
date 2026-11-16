#if DEBUG
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    @Suite
    struct MetricKitPayloadSummaryTests {
        @Test("A metric payload names the app's version and build and counts its groups of metrics")
        func metrics() {
            let json = """
            {
              "appVersion": "1.2",
              "metaData": {"appBuildVersion": "34", "osVersion": "iPhone OS 26.1", "deviceType": "iPhone17,1"},
              "applicationLaunchMetrics": {"histogrammedTimeToFirstDrawKey": {"histogramNumBuckets": 1}},
              "applicationResponsivenessMetrics": {},
              "diskIOMetrics": {"cumulativeLogicalWrites": "1,200 kB"},
              "memoryMetrics": {"peakMemoryUsage": "200,000 kB"},
              "signpostMetrics": [],
              "gpuMetrics": null,
              "timeStampBegin": "2025-11-15 00:00:00 +0000",
              "timeStampEnd": "2025-11-16 00:00:00 +0000"
            }
            """
            let expected = MetricKitPayloadSummary.metrics(appVersion: "1.2 (34)", sections: 5)

            let actual = MetricKitPayloadSummary(kind: .metrics, json: Data(json.utf8))

            #expect(actual == expected)
            #expect(actual.text == "App 1.2 (34) · 5 metric groups")
        }

        @Test("A metric payload with one group and no version says so in the singular")
        func oneMetricGroup() {
            let actual = MetricKitPayloadSummary(kind: .metrics, json: Data(#"{"cpuMetrics":{}}"#.utf8))

            #expect(actual == .metrics(appVersion: nil, sections: 1))
            #expect(actual.text == "1 metric group")
        }

        @Test("The version alone, or the build alone, is named as it is")
        func partialVersion() {
            let versionOnly = MetricKitPayloadSummary(kind: .metrics, json: Data(#"{"appVersion":"2.0"}"#.utf8))
            let buildOnly = MetricKitPayloadSummary(kind: .metrics, json: Data(#"{"metaData":{"appBuildVersion":"7"}}"#.utf8))

            #expect(versionOnly.text == "App 2.0 · 0 metric groups")
            #expect(buildOnly.text == "App (7) · 0 metric groups")
        }

        @Test("A diagnostic payload counts each kind of diagnostic, singular and plural")
        func diagnostics() {
            let json = """
            {
              "crashDiagnostics": [{}],
              "hangDiagnostics": [{}, {}],
              "cpuExceptionDiagnostics": [{}],
              "diskWriteExceptionDiagnostics": [{}, {}, {}],
              "appLaunchDiagnostics": [{}],
              "timeStampBegin": "2025-11-16 10:00:00 +0000",
              "timeStampEnd": "2025-11-16 10:00:00 +0000"
            }
            """
            let expected = MetricKitPayloadSummary.diagnostics(.init(crashes: 1, hangs: 2, cpuExceptions: 1, diskWriteExceptions: 3, slowLaunches: 1))

            let actual = MetricKitPayloadSummary(kind: .diagnostics, json: Data(json.utf8))

            #expect(actual == expected)
            #expect(actual.text == "1 crash · 2 hangs · 1 CPU exception · 3 disk-write exceptions · 1 slow launch")
        }

        @Test("A diagnostic payload of several crashes and nothing else lists only the crashes")
        func onlyCrashes() {
            let actual = MetricKitPayloadSummary(kind: .diagnostics, json: Data(#"{"crashDiagnostics":[{},{}]}"#.utf8))

            #expect(actual.text == "2 crashes")
        }

        @Test("A diagnostic payload with none of them says so")
        func noDiagnostics() {
            let actual = MetricKitPayloadSummary(kind: .diagnostics, json: Data("{}".utf8))

            #expect(actual == .diagnostics(.init()))
            #expect(actual.text == "No diagnostics")
        }

        @Test("JSON that isn't an object is unreadable")
        func unreadable() {
            let actual = MetricKitPayloadSummary(kind: .metrics, json: Data("[]".utf8))

            #expect(actual == .unreadable)
            #expect(actual.text == "Not a MetricKit payload")
        }
    }
#endif
