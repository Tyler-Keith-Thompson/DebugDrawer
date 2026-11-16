#if DEBUG
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NotificationsModelTests {
        @Test("Before the first read the center is loading; a refresh reads the settings, pending and delivered lists")
        func refresh() async {
            let center = FakeNotificationCenter(authorization: .authorized)
            center.pending = [ListedNotification(id: "p1", title: "Later")]
            center.delivered = [ListedNotification(id: "d1", title: "Earlier")]
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())
            let before = sut.center

            await sut.refresh()

            guard case let .loaded(snapshot) = sut.center else {
                Issue.record("Expected a loaded center, got \(sut.center)")
                return
            }
            #expect(before == .loading)
            #expect(snapshot.settings.authorization == .authorized)
            #expect(snapshot.pending.map(\.id) == ["p1"])
            #expect(snapshot.delivered.map(\.id) == ["d1"])
        }

        @Test("A change the source reports reads the center again")
        func change() async {
            let center = FakeNotificationCenter(authorization: .denied)
            let changes = FakeNotificationChangeSource()
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: changes)
            await sut.refresh()
            center.authorization = .authorized
            center.delivered = [ListedNotification(id: "d1", title: "Arrived in the background")]

            await changes.change()

            #expect(sut.center.snapshot?.settings.authorization == .authorized)
            #expect(sut.center.snapshot?.delivered.map(\.id) == ["d1"])
        }

        @Test("Sending a valid draft adds it under a debugdrawer identifier with the chosen delay, then reads the center again")
        func send() async throws {
            let center = FakeNotificationCenter(authorization: .authorized)
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())
            sut.draft = #"{"aps": {"alert": "Hi"}, "orderID": 7}"#
            sut.delay = .fiveSeconds
            let expected = try NotificationPayload(parsing: sut.draft)

            await sut.send()

            let added = try #require(center.added.first)
            #expect(center.added.count == 1)
            #expect(added.payload == expected)
            #expect(added.delay == .fiveSeconds)
            #expect(added.identifier.hasPrefix("debugdrawer-"))
            #expect(sut.sendState == .sent(identifier: added.identifier, delay: .fiveSeconds))
            #expect(center.authorizationRequests == 0)
            #expect(sut.center.snapshot != nil)
        }

        @Test("Sending while the user hasn't decided asks first, then sends")
        func sendAsksFirst() async {
            let center = FakeNotificationCenter(authorization: .notDetermined)
            center.answer = .authorized
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())

            await sut.send()

            #expect(center.authorizationRequests == 1)
            #expect(center.added.count == 1)
            #expect(sut.center.snapshot?.settings.authorization == .authorized)
        }

        @Test("Sending after a denial doesn't ask, and still sends: the system accepts it and shows nothing")
        func sendDenied() async {
            let center = FakeNotificationCenter(authorization: .denied)
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())

            await sut.send()

            #expect(center.authorizationRequests == 0)
            #expect(center.added.count == 1)
        }

        @Test("A draft that isn't a payload sends nothing")
        func sendInvalid() async {
            let center = FakeNotificationCenter(authorization: .authorized)
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())
            sut.draft = #"{"alert": "no aps"}"#

            await sut.send()

            #expect(center.added.isEmpty)
            #expect(sut.sendState == .idle)
        }

        @Test("A send the system refuses shows its reason")
        func sendRefused() async {
            let center = FakeNotificationCenter(authorization: .authorized)
            center.addFailure = NotificationCenterFailure(message: "Notifications are not allowed for this application")
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())

            await sut.send()

            #expect(sut.sendState == .failed(message: "Notifications are not allowed for this application"))
        }

        @Test("Requesting authorization asks, then reads the answer")
        func requestAuthorization() async {
            let center = FakeNotificationCenter(authorization: .notDetermined)
            center.answer = .denied
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())

            await sut.requestAuthorization()

            #expect(center.authorizationRequests == 1)
            #expect(sut.authorizationRequest == .idle)
            #expect(sut.center.snapshot?.settings.authorization == .denied)
        }

        @Test("A request the system can't make shows its reason")
        func requestAuthorizationFails() async {
            let center = FakeNotificationCenter(authorization: .notDetermined)
            center.authorizationFailure = NotificationCenterFailure(message: "The app isn't allowed to ask")
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())

            await sut.requestAuthorization()

            #expect(sut.authorizationRequest == .failed(message: "The app isn't allowed to ask"))
        }

        @Test("Removing a pending or delivered notification removes it from the center and from the list at once")
        func remove() async {
            let center = FakeNotificationCenter(authorization: .authorized)
            center.pending = [ListedNotification(id: "p1", title: "One"), ListedNotification(id: "p2", title: "Two")]
            center.delivered = [ListedNotification(id: "d1", title: "Three"), ListedNotification(id: "d2", title: "Four")]
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())
            await sut.refresh()

            sut.removePending("p1")
            sut.removeDelivered("d2")

            #expect(center.removedPending == [["p1"]])
            #expect(center.removedDelivered == [["d2"]])
            #expect(sut.center.snapshot?.pending.map(\.id) == ["p2"])
            #expect(sut.center.snapshot?.delivered.map(\.id) == ["d1"])
        }

        @Test("Remove All empties each list in the center and in the drawer")
        func removeAll() async {
            let center = FakeNotificationCenter(authorization: .authorized)
            center.pending = [ListedNotification(id: "p1", title: "One")]
            center.delivered = [ListedNotification(id: "d1", title: "Two")]
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())
            await sut.refresh()

            sut.removeAllPending()
            sut.removeAllDelivered()

            #expect(center.removedAllPending == 1)
            #expect(center.removedAllDelivered == 1)
            #expect(sut.center.snapshot?.pending.isEmpty == true)
            #expect(sut.center.snapshot?.delivered.isEmpty == true)
        }

        @Test("Removing before the first read tells the center and changes no list")
        func removeBeforeRead() {
            let center = FakeNotificationCenter(authorization: .authorized)
            let sut = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())

            sut.removePending("p1")

            #expect(center.removedPending == [["p1"]])
            #expect(sut.center == .loading)
        }

        @Test("A reported registration shows: a token, or the reason registering failed")
        func registration() {
            let token = Data([0xAB, 0xCD])
            let sut = NotificationsModel(
                registration: .notRegistered, client: FakeNotificationCenter(authorization: .authorized), changes: FakeNotificationChangeSource()
            )

            sut.update(.registered(deviceToken: token))
            let registered = sut.registration
            sut.update(.failed(message: "no valid aps-environment entitlement string found for application"))
            let failed = sut.registration

            #expect(registered == .registered(deviceToken: token))
            #expect(failed == .failed(message: "no valid aps-environment entitlement string found for application"))
        }
    }

    extension NotificationCenterState {
        fileprivate var snapshot: NotificationCenterSnapshot? {
            guard case let .loaded(snapshot) = self else { return nil }
            return snapshot
        }
    }
#endif
