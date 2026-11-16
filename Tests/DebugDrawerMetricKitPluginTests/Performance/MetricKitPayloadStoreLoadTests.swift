// What keeping fifty payloads costs at launch. The store exists in debug builds only, so it is
// measured there; `--config=release` builds this target without it, and runs ReleaseInstallTests
// instead.
#if DEBUG
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    // install() reads every kept payload on the main actor at startup, and each delivery checks it
    // against them. Fifty payloads of about 60 kB each (a day's metrics with histograms) load in a
    // few milliseconds on an Apple silicon Mac in debug builds; the bounds are several times that,
    // so a loaded machine passes and a change that parses or formats every payload's JSON at load
    // fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct MetricKitPayloadStoreLoadTests {
        @Test("Loading fifty kept payloads of over 40 kB takes under 100 ms, and a delivery into the full store under 20 ms")
        func loadFull() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let filler: [String] = (0 ..< 800).map { (index: Int) -> String in
                #""bucket\#(index)":{"bucketStart":"\#(index) ms","bucketEnd":"\#(index + 1) ms","bucketCount":\#(index)}"#
            }
            let histogram = "{" + filler.joined(separator: ",") + "}"
            let seed = MetricKitPayloadStore(directory: directory)
            seed.receive((0 ..< 50).map { day in
                let json: String = #"{"day":\#(day),"applicationLaunchMetrics":\#(histogram)}"#
                let begin = Date(timeIntervalSince1970: TimeInterval(day * 86400))
                let end = Date(timeIntervalSince1970: TimeInterval((day + 1) * 86400))
                return ReceivedMetricKitPayload(kind: .metrics, json: Data(json.utf8), begin: begin, end: end)
            })
            let size = try #require(seed.payloads.first).json.count
            let clock = ContinuousClock()
            var loaded: MetricKitPayloadStore?

            let loadTime = clock.measure {
                loaded = MetricKitPayloadStore(directory: directory)
            }
            let sut = try #require(loaded)
            let incoming = ReceivedMetricKitPayload(
                kind: .metrics, json: Data(#"{"day":50,"applicationLaunchMetrics":\#(histogram)}"#.utf8),
                begin: Date(timeIntervalSince1970: 50 * 86400), end: Date(timeIntervalSince1970: 51 * 86400)
            )
            let receiveTime = clock.measure {
                sut.receive([incoming])
            }

            print("MetricKit: loading 50 payloads of \(size) bytes takes \(loadTime); a delivery into the full store \(receiveTime)")
            #expect(size > 40000)
            #expect(sut.payloads.count == 50)
            #expect(loadTime < .milliseconds(100))
            #expect(receiveTime < .milliseconds(20))
        }
    }
#endif
