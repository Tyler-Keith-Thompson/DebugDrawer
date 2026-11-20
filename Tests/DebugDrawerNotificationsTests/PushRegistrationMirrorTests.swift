// The push registration mirror against real sessions, its settings read by a closure the test
// steers in place of User Notifications' center, which a test runner, having no bundle identifier,
// can't reach.
#if DEBUG
    @testable import DebugDrawerNotifications
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// Settings the test changes between reads, counting them.
    @MainActor
    private final class ScriptedSettings {
        var authorization: NotificationSettings.Authorization
        private(set) var reads = 0

        init(authorization: NotificationSettings.Authorization) {
            self.authorization = authorization
        }

        func read() async -> NotificationSettings {
            reads += 1
            return NotificationSettings(authorization: authorization, items: [])
        }
    }

    /// Holds the first read until the test releases it, then answers Denied; every later read
    /// answers Allowed at once.
    @MainActor
    private final class HeldFirstRead {
        let started: AsyncStream<Void>
        private let start: AsyncStream<Void>.Continuation
        private let released: AsyncStream<Void>
        private let release: AsyncStream<Void>.Continuation
        private var reads = 0

        init() {
            (started, start) = AsyncStream<Void>.makeStream()
            (released, release) = AsyncStream<Void>.makeStream()
        }

        func releaseFirstRead() {
            release.finish()
        }

        func read() async -> NotificationSettings {
            reads += 1
            guard reads == 1 else { return NotificationSettings(authorization: .authorized, items: []) }
            start.yield()
            for await _ in released {}
            return NotificationSettings(authorization: .denied, items: [])
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PushRegistrationMirrorTests {
        @Test("Nothing is served while no session is open, though the host handed over the token")
        func nothingOutsideSession() {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = PushRegistrationMirror(
                sessions: sessions, environment: PushEnvironment(server: .sandbox, source: .host),
                settings: { NotificationSettings(authorization: .authorized, items: []) }
            )

            sut.didRegisterForRemoteNotifications(withDeviceToken: Data([0xAB, 0x01]))

            let expected = PushRegistrationMirror.Snapshot(sessionID: nil, registration: nil, environment: nil, settings: nil)
            #expect(sut.snapshot == expected)
        }

        @Test("A session opening serves the token as lowercase hexadecimal, the environment and the settings")
        func servedInSession() async {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let environment = PushEnvironment(server: .sandbox, source: .host)
            let settings = NotificationSettings(authorization: .provisional, items: [.init(name: "Alerts", value: "On")])
            let sut = PushRegistrationMirror(sessions: sessions, environment: environment, settings: { settings })
            sut.didRegisterForRemoteNotifications(withDeviceToken: Data([0xAB, 0x01, 0xFF]))

            sessions.perform(.open(duration: 60))
            var served: PushRegistrationMirror.Snapshot?
            for await snapshot in sut.$snapshot.values where snapshot.settings != nil {
                served = snapshot
                break
            }

            let expected = PushRegistrationMirror.Snapshot(
                sessionID: sessions.snapshot.session?.id, registration: .registered(deviceToken: "ab01ff"),
                environment: environment, settings: settings
            )
            #expect(served == expected)
        }

        @Test("Before the app registers, a session is served notRegistered; a token arriving in it is served at once")
        func tokenArrivesDuringSession() {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = PushRegistrationMirror(
                sessions: sessions, environment: nil, settings: { NotificationSettings(authorization: .denied, items: []) }
            )
            sessions.perform(.open(duration: 60))
            let before = sut.snapshot.registration

            sut.didRegisterForRemoteNotifications(withDeviceToken: Data([0x00, 0x10]))

            #expect(before == .notRegistered)
            #expect(sut.snapshot.registration == .registered(deviceToken: "0010"))
            #expect(sut.snapshot.environment == nil)
        }

        @Test("A registration failure is served as its message")
        func failureServed() {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = PushRegistrationMirror(
                sessions: sessions, environment: nil, settings: { NotificationSettings(authorization: .denied, items: []) }
            )
            let failure = NSError(domain: "APNs", code: 3000, userInfo: [NSLocalizedDescriptionKey: "no valid aps-environment entitlement"])
            sut.didFailToRegisterForRemoteNotifications(withError: failure)

            sessions.perform(.open(duration: 60))

            #expect(sut.snapshot.registration == .failed(message: "no valid aps-environment entitlement"))
        }

        @Test("The token is withdrawn as the session ends")
        func withdrawnAtEnd() {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = PushRegistrationMirror(
                sessions: sessions, environment: PushEnvironment(server: .production, source: .host),
                settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            sut.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))
            sessions.perform(.open(duration: 60))
            let during = sut.snapshot.registration

            sessions.end()

            #expect(during == .registered(deviceToken: "cafe"))
            #expect(sut.snapshot == PushRegistrationMirror.Snapshot(sessionID: nil, registration: nil, environment: nil, settings: nil))
        }

        @Test("The token is withdrawn as the session expires")
        func withdrawnAtExpiry() {
            let clock = MovableClock(Date(timeIntervalSince1970: 1_800_000_000))
            let timer = ManualTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 60, auditCapacity: 100, clock: clock, timer: timer)
            let sut = PushRegistrationMirror(
                sessions: sessions, environment: nil, settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            sut.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))
            sessions.perform(.open(duration: 60))
            let during = sut.snapshot.registration

            clock.set(Date(timeIntervalSince1970: 1_800_000_060))
            timer.fireNow()

            #expect(during == .registered(deviceToken: "cafe"))
            #expect(sut.snapshot.sessionID == nil)
            #expect(sut.snapshot.registration == nil)
        }

        @Test("Refresh reads the settings again within a session, and does nothing outside one")
        func refresh() async {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let center = ScriptedSettings(authorization: .notDetermined)
            let sut = PushRegistrationMirror(sessions: sessions, environment: nil, settings: center.read)
            sut.perform(.refresh)
            let readsOutside = center.reads
            sessions.perform(.open(duration: 60))
            for await snapshot in sut.$snapshot.values where snapshot.settings?.authorization == .notDetermined {
                break
            }
            center.authorization = .authorized

            sut.perform(.refresh)
            var refreshed: NotificationSettings?
            for await snapshot in sut.$snapshot.values where snapshot.settings?.authorization == .authorized {
                refreshed = snapshot.settings
                break
            }

            #expect(readsOutside == 0)
            #expect(refreshed == NotificationSettings(authorization: .authorized, items: []))
            #expect(center.reads == 2)
        }

        @Test("Settings read for a session that ended before they came are dropped")
        func lateSettingsDropped() async {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let center = HeldFirstRead()
            let sut = PushRegistrationMirror(sessions: sessions, environment: nil, settings: center.read)
            var starts = center.started.makeAsyncIterator()
            sessions.perform(.open(duration: 60))
            await starts.next()
            sessions.end()

            center.releaseFirstRead()
            sessions.perform(.open(duration: 60))
            let secondSession = sessions.snapshot.session?.id
            var served: PushRegistrationMirror.Snapshot?
            for await snapshot in sut.$snapshot.values where snapshot.settings != nil {
                served = snapshot
                break
            }

            #expect(served?.sessionID == secondSession)
            #expect(served?.settings?.authorization == .authorized)
            #expect(sut.snapshot.settings?.authorization == .authorized)
        }

        @Test("Under a grant policy, a session whose grant doesn't list the capability is served nothing")
        func grantWithoutCapability() {
            let policy = DebugDrawerGrantPolicy(
                verifier: AcceptingGrantVerifier(audience: "com.example.app", capabilities: ["DebugDrawer.LogLevels"]), audience: "com.example.app"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: policy)
            let sut = PushRegistrationMirror(
                sessions: sessions, environment: nil, settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            sut.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))

            sessions.perform(.open(duration: 60, grant: "grant-1"))

            #expect(sessions.snapshot.isActive)
            let expected = PushRegistrationMirror.Snapshot(
                sessionID: sessions.snapshot.session?.id, registration: nil, environment: nil, settings: nil
            )
            #expect(sut.snapshot == expected)
        }

        @Test("Under a grant policy, a session whose grant lists the capability is served the token")
        func grantWithCapability() {
            let policy = DebugDrawerGrantPolicy(
                verifier: AcceptingGrantVerifier(audience: "com.example.app", capabilities: [PushRegistrationMirror.pluginID]),
                audience: "com.example.app"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: policy)
            let sut = PushRegistrationMirror(
                sessions: sessions, environment: nil, settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            sut.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))

            sessions.perform(.open(duration: 60, grant: "grant-2"))

            #expect(sut.snapshot.registration == .registered(deviceToken: "cafe"))
        }
    }
#endif
