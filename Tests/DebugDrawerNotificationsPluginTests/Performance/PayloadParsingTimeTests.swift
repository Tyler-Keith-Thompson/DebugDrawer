// What checking the payload costs as it is typed. The plugin exists in debug builds only, so it is
// measured there; `--config=release` builds this target without it, and runs ReleaseInstallTests
// instead.
#if DEBUG
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    // The editor parses the payload on every keystroke, on the main actor. APNs takes at most 4 KB,
    // which parses in well under a millisecond on an Apple silicon Mac in debug builds; the bound is
    // many times that, so a loaded machine passes and a parse that walks the text once per key
    // fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PayloadParsingTimeTests {
        @Test("Parsing a 4 KB payload, the most APNs takes, a hundred times takes under 100 ms")
        func largestPayload() throws {
            let custom = (0 ..< 175).map { "\"key\($0)\": \"value \($0)\"" }.joined(separator: ", ")
            let text = """
            {"aps": {"alert": {"title": "Order shipped", "subtitle": "Today", "body": "Your order is on its way"}, \
            "badge": 3, "sound": "default", "category": "ORDER", "thread-id": "orders"}, \(custom)}
            """
            let clock = ContinuousClock()
            var parsed: [NotificationPayload] = []

            let elapsed = try clock.measure {
                for _ in 0 ..< 100 {
                    try parsed.append(NotificationPayload(parsing: text))
                }
            }

            print("Notifications: parsing a \(text.utf8.count)-byte payload 100 times takes \(elapsed)")
            #expect(text.utf8.count > 3900)
            #expect(text.utf8.count <= NotificationPayload.maximumSize)
            #expect(parsed.count == 100)
            #expect(elapsed < .milliseconds(100))
        }
    }
#endif
