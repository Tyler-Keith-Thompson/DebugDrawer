import DebugDrawerAppInfo
import DebugDrawerReceiver
import Foundation
import Testing

// Registrations the types can't rule out: a field with no key, and two fields under one key, which
// would leave one of them unread. The state refuses both as it is made.
@MainActor
@Suite
struct AppStateValidationTests {
    @Test("A field with an empty key throws emptyKey")
    func emptyKey() {
        let sessions = DebugDrawerSessions(maximumDuration: 60)
        let fields = [DebugDrawerAppStateField("") { "pro" }]

        #expect(throws: DebugDrawerAppState.InvalidField.emptyKey) {
            _ = try DebugDrawerAppState(sessions: sessions, values: fields)
        }
    }

    @Test("Two fields under one key throw duplicateKey")
    func repeatedKey() {
        let sessions = DebugDrawerSessions(maximumDuration: 60)
        let fields = [DebugDrawerAppStateField("plan") { "pro" }, DebugDrawerAppStateField("plan") { "free" }]

        #expect(throws: DebugDrawerAppState.InvalidField.duplicateKey) {
            _ = try DebugDrawerAppState(sessions: sessions, values: fields)
        }
    }

    @Test("One field, and no fields, are taken")
    func oneAndNone() throws {
        let sessions = DebugDrawerSessions(maximumDuration: 60)

        _ = try DebugDrawerAppState(sessions: sessions, values: [DebugDrawerAppStateField("plan") { "pro" }])
        _ = try DebugDrawerAppState(sessions: sessions)
    }
}
