#if DEBUG
    @testable import DebugDrawerCrashReportsPlugin
    import Foundation
    import Testing

    @Suite
    struct CrashDiagnosticTests {
        @Test("A MetricKit crash reads as its signal, exception message, version and the crashed thread's frames")
        func crash() throws {
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
                        "sampleCount": 1,
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
              "diagnosticMetaData": {
                "appVersion": "1.2",
                "appBuildVersion": "34",
                "signal": 11,
                "exceptionType": 1,
                "terminationReason": "Namespace SIGNAL, Code 11",
                "objectiveCexceptionReason": { "composedMessage": "index 5 beyond bounds" }
              }
            }
            """
            let date = Date(timeIntervalSince1970: 1_763_290_000)
            let id = UUID()
            let expected = CrashReport(
                id: id,
                date: date,
                title: "SIGSEGV",
                reason: "index 5 beyond bounds",
                appVersion: "1.2 (34)",
                frames: ["0 Example 0x100004000 + 16384", "1 Example 0x100004100 + 16640", "2 dyld ?"],
                source: .metricKit,
                isSeen: false
            )
            let sut = CrashDiagnostic(json: Data(json.utf8), date: date)

            let actual = sut.report(id: id)

            #expect(actual == expected)
        }

        @Test("A crash without a signal is named by its exception type, its reason the termination reason")
        func exceptionType() throws {
            let json = #"{ "diagnosticMetaData": { "exceptionType": 10, "terminationReason": "Watchdog" } }"#
            let sut = CrashDiagnostic(json: Data(json.utf8), date: .distantPast)

            let actual = try #require(sut.report(id: UUID()))

            #expect(actual.title == "Exception type 10")
            #expect(actual.reason == "Watchdog")
            #expect(actual.appVersion == nil)
            #expect(actual.frames.isEmpty)
        }

        @Test("An empty diagnostic is a crash with nothing more known")
        func empty() throws {
            let sut = CrashDiagnostic(json: Data("{}".utf8), date: .distantPast)

            let actual = try #require(sut.report(id: UUID()))

            #expect(actual.title == "Crash")
            #expect(actual.reason == nil)
        }

        @Test("JSON that isn't a diagnostic is no report", arguments: ["", "[1, 2]", "not json", #"{ "callStackTree": 3 }"#])
        func garbage(json: String) {
            let sut = CrashDiagnostic(json: Data(json.utf8), date: .distantPast)

            let actual = sut.report(id: UUID())

            #expect(actual == nil)
        }
    }
#endif
