// What the requests refuse as they are made. Real in every build, so these run in debug and
// release alike.
import DebugDrawerAppStateReset
import DebugDrawerReceiver
import Testing

@MainActor
@Suite
struct AppStateResetRequestsValidationTests {
    @Test("Naming the keychain among the allowed categories throws KeychainAsCategory: it is allowed with allowingKeychain alone")
    func keychainAmongCategories() {
        let categories: Set<AppStateReset.Category> = [.caches, .keychain]

        #expect(throws: AppStateResetRequests.KeychainAsCategory.self) {
            _ = try AppStateResetRequests(sessions: DebugDrawerSessions(maximumDuration: 60), allowing: categories)
        }
    }

    @Test("The keychain named with allowingKeychain alone is allowed")
    func keychainThroughItsOwnSwitch() throws {
        let expected: Set<AppStateReset.Category> = [.caches, .keychain]

        let sut = try AppStateResetRequests(sessions: DebugDrawerSessions(maximumDuration: 60), allowing: [.caches], allowingKeychain: true)

        #expect(sut.allowed == expected)
    }
}
