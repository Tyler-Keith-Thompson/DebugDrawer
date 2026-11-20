// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    import DebugDrawerReceiver
    import Testing

    @Suite
    struct AuthActionsExitTests {
        @Test("Two auth actions with one ID trap")
        func repeatedActionIDTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = DebugDrawerAuthActions(actions: [
                        .logOut { .succeeded },
                        DebugDrawerAuthAction("log-out", title: "Log Out Again") { .succeeded }
                    ])
                }
            }
        }
    }
#endif
