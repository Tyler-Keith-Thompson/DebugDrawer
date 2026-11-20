// Exit tests, in a file of their own: builds for platforms that can't start a child process leave
// it out.
#if DEBUG && os(macOS)
    @testable import DebugDrawerAppStateReset
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @Suite
    struct AppStateResetRequestsExitTests {
        @Test("Naming the keychain among the allowed categories traps: it is allowed with allowingKeychain alone")
        func keychainAmongCategoriesTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = AppStateResetRequests(sessions: DebugDrawerSessions(maximumDuration: 60), allowing: [.caches, .keychain])
                }
            }
        }
    }
#endif
