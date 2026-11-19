#if DEBUG
    import Combine
    import Foundation
    import os

    /// The device token the app reported and what the notification center holds, read again on
    /// every change the source reports and after each of the drawer's own actions; and the payload
    /// being written, sent on request.
    @MainActor
    final class NotificationsModel: ObservableObject {
        @Published private(set) var registration: RemoteRegistration
        @Published private(set) var center: NotificationCenterState = .loading
        @Published private(set) var authorizationRequest: AuthorizationRequestState = .idle
        @Published private(set) var sendState: SendState = .idle
        /// The APNs payload in the editor.
        @Published var draft = NotificationsModel.starterPayload
        @Published var delay = SendDelay.now

        /// What the editor starts with: the smallest payload that shows a banner.
        static let starterPayload = """
        {
          "aps": {
            "alert": {
              "title": "Hello",
              "body": "Sent from the debug drawer"
            },
            "sound": "default"
          }
        }
        """

        private static let logger = Logger(subsystem: "DebugDrawerNotificationsPlugin", category: "NotificationsModel")
        private let client: any NotificationCenterClient
        /// Kept for the model's life: the source reports only while someone holds it.
        private let changes: any NotificationChangeSource
        /// Counts reads, so a read that finishes after a later one began is dropped rather than
        /// overwriting newer state.
        private var latestRead = 0

        /// - Parameters:
        ///   - registration: What the app has reported so far.
        ///   - client: Reads and changes the notification center.
        ///   - changes: Says when to read it again; observed from now on.
        init(registration: RemoteRegistration, client: any NotificationCenterClient, changes: any NotificationChangeSource) {
            self.registration = registration
            self.client = client
            self.changes = changes
            changes.observe { [weak self] in await self?.refresh() }
        }

        /// Whether the model reads again on each change the source reports: from its creation
        /// until the last drawer uninstalls the plugin, and again once one installs it.
        private(set) var isObserving = true
        /// The drawers the plugin over this model is installed in.
        private var installedDrawers: Set<ObjectIdentifier> = []

        /// Counts `drawer` as one the plugin is installed in. If an uninstall stopped the model,
        /// observes the source again and reads the center again.
        func install(in drawer: ObjectIdentifier) {
            installedDrawers.insert(drawer)
            guard !isObserving else { return }
            isObserving = true
            changes.observe { [weak self] in await self?.refresh() }
            Task { await refresh() }
        }

        /// Uncounts `drawer`. Once no drawer has the plugin, stops observing the source and drops
        /// what was read; a read on its way is dropped too.
        func uninstall(from drawer: ObjectIdentifier) {
            installedDrawers.remove(drawer)
            guard installedDrawers.isEmpty, isObserving else { return }
            isObserving = false
            changes.stop()
            latestRead += 1
            center = .loading
        }

        /// Shows what the app reported last.
        func update(_ registration: RemoteRegistration) {
            self.registration = registration
        }

        /// Reads the settings, the pending requests and the delivered notifications again.
        func refresh() async {
            latestRead += 1
            let read = latestRead
            let settings = await client.settings()
            let pending = await client.pendingNotifications()
            let delivered = await client.deliveredNotifications()
            guard read == latestRead else {
                Self.logger.debug("Dropped a read that a later one overtook")
                return
            }
            Self.logger.debug("Read \(pending.count) pending and \(delivered.count) delivered notifications")
            center = .loaded(NotificationCenterSnapshot(settings: settings, pending: pending, delivered: delivered))
        }

        /// Shows the system's prompt for alerts, badges and sounds, then reads everything again.
        func requestAuthorization() async {
            authorizationRequest = .requesting
            do {
                try await client.requestAuthorization()
                authorizationRequest = .idle
            } catch {
                Self.logger.error("Asking for authorization failed: \(error.message, privacy: .public)")
                authorizationRequest = .failed(message: error.message)
            }
            await refresh()
        }

        /// Sends the draft as a local notification after `delay`, first asking for authorization
        /// if the user hasn't decided; a draft that isn't a payload sends nothing.
        func send() async {
            guard let payload = try? NotificationPayload(parsing: draft) else { return }
            sendState = .sending
            if await client.settings().authorization == .notDetermined {
                // A refusal or failure is shown by the authorization it leaves; the request is
                // added either way, as the system accepts it and shows nothing.
                try? await client.requestAuthorization()
            }
            let identifier = "debugdrawer-\(UUID().uuidString)"
            do {
                try await client.add(payload, identifier: identifier, delay: delay)
                Self.logger.info("Sent a payload as \(identifier, privacy: .public)")
                sendState = .sent(identifier: identifier, delay: delay)
            } catch {
                Self.logger.error("The system refused the notification: \(error.message, privacy: .public)")
                sendState = .failed(message: error.message)
            }
            await refresh()
        }

        // The removals update the lists themselves rather than read them again: the center
        // removes on a queue of its own, so a read right after can still list what was removed.
        // The next read (on becoming active, after a send, on Refresh) shows the center's own.

        func removePending(_ id: ListedNotification.ID) {
            client.removePendingNotifications(withIdentifiers: [id])
            change { $0.pending.removeAll { $0.id == id } }
        }

        func removeAllPending() {
            client.removeAllPendingNotifications()
            change { $0.pending = [] }
        }

        func removeDelivered(_ id: ListedNotification.ID) {
            client.removeDeliveredNotifications(withIdentifiers: [id])
            change { $0.delivered.removeAll { $0.id == id } }
        }

        func removeAllDelivered() {
            client.removeAllDeliveredNotifications()
            change { $0.delivered = [] }
        }

        /// Applies `edit` to what was last read; a read on its way is dropped, as it may predate
        /// the removal.
        private func change(_ edit: (inout NotificationCenterSnapshot) -> Void) {
            guard case var .loaded(snapshot) = center else { return }
            latestRead += 1
            edit(&snapshot)
            center = .loaded(snapshot)
        }
    }
#endif
