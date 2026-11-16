#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @Suite
    struct HangDiagnosticTests {
        @Test("A MetricKit hang reads as its duration, the payload's date and the attributed thread's frames")
        func hang() throws {
            let json = """
            {
              "version": "1.0.0",
              "callStackTree": {
                "callStackPerThread": true,
                "callStacks": [
                  {
                    "threadAttributed": false,
                    "callStackRootFrames": [{ "binaryName": "libsystem_kernel.dylib", "address": 4096, "offsetIntoBinaryTextSegment": 16 }]
                  },
                  {
                    "threadAttributed": true,
                    "callStackRootFrames": [
                      {
                        "binaryName": "Example",
                        "address": 4294983680,
                        "offsetIntoBinaryTextSegment": 16384,
                        "subFrames": [
                          {
                            "binaryName": "Example", "address": 4294983936, "offsetIntoBinaryTextSegment": 16640,
                            "subFrames": [{ "binaryName": "dyld" }]
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              "diagnosticMetaData": { "appVersion": "1.2", "hangDuration": "3 sec" }
            }
            """
            let date = Date(timeIntervalSince1970: 1_763_290_000)
            let id = UUID()
            let expected = HangEvent(
                id: id,
                date: date,
                duration: .seconds(3),
                frames: ["0 Example 0x100004000 + 16384", "1 Example 0x100004100 + 16640", "2 dyld ?"],
                source: .metricKit,
                isSeen: false
            )
            let sut = HangDiagnostic(json: Data(json.utf8), duration: .seconds(3), date: date)

            let actual = sut.event(id: id)

            #expect(actual == expected)
        }

        @Test("With no thread attributed, the first thread's frames are used")
        func firstThread() throws {
            let json = """
            {"callStackTree": {"callStacks": [{"callStackRootFrames": [{"binaryName": "Example", "address": 16}]}, {"callStackRootFrames": []}]}}
            """
            let sut = HangDiagnostic(json: Data(json.utf8), duration: .seconds(1), date: Date(timeIntervalSince1970: 0))

            let actual = try #require(sut.event(id: UUID()))

            #expect(actual.frames == ["0 Example 0x10"])
        }

        @Test("A diagnostic with no call stacks is a hang with no frames")
        func noStacks() throws {
            let json = #"{"callStackTree": {"callStacks": []}}"#
            let sut = HangDiagnostic(json: Data(json.utf8), duration: .seconds(1), date: Date(timeIntervalSince1970: 0))

            let actual = try #require(sut.event(id: UUID()))

            #expect(actual.frames.isEmpty)
        }

        @Test("JSON that isn't a hang diagnostic is no hang")
        func garbage() {
            let sut = HangDiagnostic(json: Data(#"{"something": "else"}"#.utf8), duration: .seconds(1), date: Date(timeIntervalSince1970: 0))

            let actual = sut.event(id: UUID())

            #expect(actual == nil)
        }
    }
#endif
