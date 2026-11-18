// What typing in the log's filter costs the main thread. The log exists in debug builds only, so
// it is measured there; `--config=release` builds this target without it, and runs
// ReleaseInstallTests instead.
#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // The filter runs on the main thread at every keystroke, over every request the log holds.
    // Measured against the work it must not repeat: parsing and pretty-printing the same 200 JSON
    // bodies once. Each keystroke's query matches near the start of every body, so a filter that
    // reads text worked out when the bodies arrived does almost nothing, and the six keystrokes
    // take a small share of one parse; a filter that parses each body takes six parses or more.
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkFilterSpeedTests {
        @Test("Typing six keystrokes into the filter over 200 JSON responses costs less than parsing their bodies once")
        func filterDoesNotParse() {
            let items = (0 ..< 400).map { #"{"id":\#($0),"name":"user \#($0)","roles":["reader","writer"],"active":true}"# }
            let body = Data(#"{"aaa":"needle","items":[\#(items.joined(separator: ","))]}"#.utf8)
            let entries = (0 ..< 200).map { index in
                NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: Double(index)), method: "GET",
                    url: "https://api.example.com/v1/users?page=\(index)", host: "api.example.com", path: "/v1/users",
                    requestHeaders: [:], requestBody: nil, statusCode: 200, responseBody: body, isComplete: true
                )
            }
            let keystrokes = ["n", "ne", "nee", "need", "needl", "needle"]
            let clock = ContinuousClock()
            let parseTime = clock.measure {
                for entry in entries {
                    _ = entry.responseBody?.prettyBody?.lowercased()
                }
            }
            var matches: [Int] = []

            let filterTime = clock.measure {
                for query in keystrokes {
                    matches.append(NetworkStore.entries(entries, matching: .all, text: query).count)
                }
            }

            print("Network: filtering 200 JSON responses, six keystrokes take \(filterTime); parsing their bodies once \(parseTime)")
            #expect(matches == Array(repeating: 200, count: keystrokes.count))
            #expect(filterTime < parseTime)
        }
    }
#endif
