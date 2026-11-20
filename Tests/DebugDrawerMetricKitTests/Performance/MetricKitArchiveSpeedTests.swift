// What keeping a payload costs the main actor, where MetricKit's deliveries land: a diagnostic
// payload near the size limit (a megabyte of call-stack frames) is parsed, redacted, written and
// compared with the ones kept. Twenty of them take about a second on an Apple silicon Mac in a
// debug build; the bound is several times that, so a loaded machine passes and a change that
// re-reads every file or redacts each payload kept on every delivery fails. `--config=release` builds this
// target without DEBUG and runs ReleaseMetricKitTests instead.
#if DEBUG
    @testable import DebugDrawerMetricKit
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct MetricKitArchiveSpeedTests {
        @Test("Keeping twenty diagnostic payloads of nearly a megabyte each, ten of them into a full archive, takes under 5 s")
        func keepLargePayloads() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "MetricKitArchiveSpeedTests-\(UUID().uuidString)")
            let sut = MetricKitPayloadArchive(directory: directory, capacity: 10, maximumPayloadSize: MetricKitPayloadsMirror.maximumPayloadSize)
            func payload(_ index: Int) -> ReceivedMetricKitPayload {
                let frame = #"{"binaryName":"ExampleApp","binaryUUID":"70B89F27-1634-3580-A695-57CDB41D7743","#
                    + #""offsetIntoBinaryTextSegment":123456,"address":4310052416,"sampleCount":1}"#
                let frames = Array(repeating: frame, count: 5500).joined(separator: ",")
                let json = #"{"index":\#(index),"crashDiagnostics":[{"callStackTree":{"callStacks":[{"callStackRootFrames":[\#(frames)]}]}}]}"#
                return ReceivedMetricKitPayload(kind: .diagnostics, json: Data(json.utf8), end: Date(timeIntervalSince1970: Double(index)))
            }
            let payloads = (0 ..< 20).map(payload)
            let clock = ContinuousClock()
            var changes = 0

            let elapsed = clock.measure {
                for received in payloads where sut.receive([received], redaction: .standard, at: Date()) {
                    changes += 1
                }
            }

            #expect(elapsed < .seconds(5))
            #expect(changes == 20)
            #expect(sut.payloads.count == 10)
            #expect(sut.payloads.allSatisfy { $0.json.count <= MetricKitPayloadsMirror.maximumPayloadSize })
        }
    }
#endif
