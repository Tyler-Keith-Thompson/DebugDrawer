#if DEBUG
    @testable import DebugDrawerNotificationsPlugin
    import Foundation

    /// A notification center the test fills: answers with the settings and lists it holds,
    /// records every request and removal, and on authorization sets what the user would answer.
    @MainActor
    final class FakeNotificationCenter: NotificationCenterClient {
        struct AddedRequest: Equatable {
            let payload: NotificationPayload
            let identifier: String
            let delay: SendDelay
        }

        var authorization: NotificationSettings.Authorization
        /// What a request for authorization leaves behind, as the user's answer would.
        var answer: NotificationSettings.Authorization = .authorized
        var pending: [ListedNotification] = []
        var delivered: [ListedNotification] = []
        /// The failure each `add` throws, if any.
        var addFailure: NotificationCenterFailure?
        /// The failure each authorization request throws, if any.
        var authorizationFailure: NotificationCenterFailure?
        private(set) var authorizationRequests = 0
        private(set) var added: [AddedRequest] = []
        private(set) var removedPending: [[String]] = []
        private(set) var removedDelivered: [[String]] = []
        private(set) var removedAllPending = 0
        private(set) var removedAllDelivered = 0
        private(set) var reads = 0

        init(authorization: NotificationSettings.Authorization) {
            self.authorization = authorization
        }

        func settings() async -> NotificationSettings {
            reads += 1
            return NotificationSettings(authorization: authorization, items: [.init(name: "Alerts", value: "On")])
        }

        func requestAuthorization() async throws(NotificationCenterFailure) {
            authorizationRequests += 1
            if let authorizationFailure { throw authorizationFailure }
            authorization = answer
        }

        func pendingNotifications() async -> [ListedNotification] {
            pending
        }

        func deliveredNotifications() async -> [ListedNotification] {
            delivered
        }

        func add(_ payload: NotificationPayload, identifier: String, delay: SendDelay) async throws(NotificationCenterFailure) {
            if let addFailure { throw addFailure }
            added.append(AddedRequest(payload: payload, identifier: identifier, delay: delay))
        }

        func removePendingNotifications(withIdentifiers identifiers: [String]) {
            removedPending.append(identifiers)
        }

        func removeAllPendingNotifications() {
            removedAllPending += 1
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
            removedDelivered.append(identifiers)
        }

        func removeAllDeliveredNotifications() {
            removedAllDelivered += 1
        }
    }

    /// Holds the model's callback so the test can report a change, as the app becoming active
    /// would.
    @MainActor
    final class FakeNotificationChangeSource: NotificationChangeSource {
        private var onChange: (@MainActor () async -> Void)?

        func observe(_ onChange: @escaping @MainActor () async -> Void) {
            self.onChange = onChange
        }

        /// How many times the model stopped observing.
        private(set) var stops = 0

        /// Whether the model is observing: it called `observe` and hasn't stopped since.
        var isObserving: Bool {
            onChange != nil
        }

        func stop() {
            stops += 1
            onChange = nil
        }

        /// Reports a change and returns once the model has handled it.
        func change() async {
            await onChange?()
        }
    }
#endif
