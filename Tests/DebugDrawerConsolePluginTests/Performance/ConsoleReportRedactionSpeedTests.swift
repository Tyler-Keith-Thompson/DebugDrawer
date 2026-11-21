// What masking a whole log costs as a report or Copy All is made. The lines and the Console's copy
// exist in debug builds only, so it is measured there; `--config=release` builds this target
// without it, and runs ReleaseInstallTests instead.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // 50,000 lines, each with a query string, a quoted JSON pair and two metadata fields, one of
    // them sensitive, masked by the standard rules. In debug builds on an Apple silicon Mac the
    // masked copy took about 1.3 s and 100,000 lines about 2.5 s; copying the same 50,000 lines with
    // no rules took about 0.2 s. The bound is several times the masked figure, so a loaded machine
    // passes, and twice the lines must cost less than three times as much, so a pass that goes back
    // over the text per pair (quadratic in a line's pairs or a log's lines) fails.
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleReportRedactionSpeedTests {
        @Test("Masking 50,000 lines for the report takes under 6 s, and twice the lines under three times that")
        func fiftyThousandLines() {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            func lines(_ count: Int) -> [LogLine] {
                (0 ..< count).map { index in
                    LogLine(
                        timestamp: started.addingTimeInterval(Double(index) / 100),
                        text: #"GET /api/v2/orders?page=\#(index)&access_token=t\#(index)&lang=en finished, "#
                            + #"body {"status": 200, "password": "p\#(index)"}"#,
                        source: .sink, level: index % 50 == 0 ? .error : .info,
                        subsystem: "com.example.shop", category: "networking",
                        metadata: ["order": "\(index * 7)", "session": "s\(index)"]
                    )
                }
            }
            let fifty = lines(50_000)
            let hundred = lines(100_000)
            let clock = ContinuousClock()

            let none = clock.measure { _ = fifty.copiedText(redactedBy: .none) }
            var masked = ""
            let fiftyTime = clock.measure { masked = fifty.copiedText(redactedBy: .standard) }
            let hundredTime = clock.measure { _ = hundred.copiedText(redactedBy: .standard) }

            print("Console: copying 50,000 lines with no rules takes \(none), masked by the standard rules \(fiftyTime)")
            print("Console: masking 100,000 lines takes \(hundredTime)")
            #expect(masked.contains("access_token=[REDACTED]&lang=en"))
            #expect(!masked.contains("access_token=t1&"))
            #expect(fiftyTime < .seconds(6))
            #expect(hundredTime < fiftyTime * 3)
        }
    }
#endif
