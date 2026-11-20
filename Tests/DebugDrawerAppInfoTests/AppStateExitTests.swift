// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    import DebugDrawerAppInfo
    import DebugDrawerReceiver
    import Foundation
    import Testing

    // The traps for registrations the types can't rule out: a field with no key, and two fields
    // under one key, which would leave one of them unread.
    @Suite
    struct AppStateExitTests {
        @Test("A field with an empty key traps")
        func emptyKeyTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = DebugDrawerAppStateField("") { "pro" }
                }
            }
        }

        @Test("Two fields under one key trap")
        func repeatedKeyTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = DebugDrawerAppState(
                        sessions: DebugDrawerSessions(maximumDuration: 60),
                        values: [DebugDrawerAppStateField("plan") { "pro" }, DebugDrawerAppStateField("plan") { "free" }]
                    )
                }
            }
        }
    }
#endif
