import Combine
import DebugDrawerReceiver
import Foundation

// The push registration capability's model, read-only: the host hands it the token APNs gave the
// app (the library can't ask for it; only the app delegate hears it), it reads the environment once
// and the settings as a session opens, and it serves all three only while a session is open.
//
// The charter's "never expose secrets (keychain values, tokens) over IPC" is read as credentials:
// an APNs device token isn't one. It names the device to APNs, and a push to it needs the company's
// APNs key or certificate besides, which the app doesn't hold. So the token goes to the sidecar, but
// only during a session, as the MetricKit mirror serves its payloads: outside one the snapshot
// holds nothing, so the snapshot file the receiver writes into the shared container holds the token
// only while someone is debugging, and is rewritten without it as the session ends or expires. The
// token is kept in memory alone, never in the defaults, a file of the app's or a log line. Under a
// grant policy a session whose grant doesn't list the capability is served nothing either: the
// sessions only check grants against commands, and this capability's point is what it serves.
//
// Rejected: serving whenever enabled (a device identifier in the shared container with nobody
// debugging); keeping the token on disk across launches (the app gets it again at each launch it
// registers); the plugin's `PushNotifications.didRegisterForRemoteNotifications` feeding it (that
// type is a debug-build no-op in release, where this runs); and a refresh on each return to the
// foreground (the sidecar asks with `refresh`, and the settings are read again as each session
// opens).

/// The app's APNs device token, push environment and notification settings, which the receiver
/// serves under ``pluginID`` while a sidecar's session is open, so an employee can aim a test push
/// at their own device.
///
/// The host makes it with the receiver's sessions, enables it with
/// `receiver.enable(.pushRegistration(mirror))`, and hands it what the app delegate hears:
///
/// ```swift
/// func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
///     pushRegistration.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
/// }
/// ```
@MainActor
public final class PushRegistrationMirror: DebugDrawerPluginModel {
    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.PushRegistration"

    /// What the app has heard of its registration for remote notifications.
    public enum Registration: Codable, Equatable, Sendable {
        /// Nothing heard yet: the app hasn't registered, or hasn't handed the mirror the token.
        case notRegistered
        /// APNs gave the app this device token, as lowercase hexadecimal, the form push tools
        /// take.
        case registered(deviceToken: String)
        /// Registering failed, for this reason.
        case failed(message: String)
    }

    /// What a sidecar sees: nothing but `nil`s while no session is open.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The open session's ID, or `nil` while none is open.
        public var sessionID: UUID?
        /// The device token, or why there is none; `nil` outside a session.
        public var registration: Registration?
        /// The APNs environment the token belongs to; `nil` outside a session, or when the app
        /// isn't signed for push and the host didn't say.
        public var environment: PushEnvironment?
        /// The notification authorization and settings as last read; `nil` outside a session and
        /// until the first read in it lands.
        public var settings: NotificationSettings?

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The open session's ID, or `nil`.
        ///   - registration: The token, or why there is none.
        ///   - environment: The APNs environment.
        ///   - settings: The notification settings.
        public init(sessionID: UUID?, registration: Registration?, environment: PushEnvironment?, settings: NotificationSettings?) {
            self.sessionID = sessionID
            self.registration = registration
            self.environment = environment
            self.settings = settings
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Reads the notification settings again, as after the employee changed them in Settings.
        case refresh
    }

    /// What is served now.
    @Published public private(set) var snapshot = Snapshot(sessionID: nil, registration: nil, environment: nil, settings: nil)

    /// The APNs environment it serves: the host's, or what the app is signed for.
    public let environment: PushEnvironment?

    private var registration = Registration.notRegistered
    private let readSettings: @MainActor () async -> NotificationSettings
    private var settingsRead: Task<Void, Never>?
    private var sessionObservation: AnyCancellable?

    /// A mirror served during `sessions`' open session, reading the settings from User
    /// Notifications' current center.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions, which the snapshot follows.
    ///   - environment: The APNs environment to serve; by default what the app is signed for
    ///     (``PushEnvironment/detected(in:)``). Pass one with ``PushEnvironment/Source/host`` where
    ///     the signature can't say, such as a simulator build.
    public convenience init(sessions: DebugDrawerSessions, environment: PushEnvironment? = .detected()) {
        self.init(sessions: sessions, environment: environment, settings: NotificationSettings.current)
    }

    /// A mirror served during `sessions`' open session, reading the settings with `settings`.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - environment: The APNs environment to serve.
    ///   - settings: Reads the notification settings.
    package init(sessions: DebugDrawerSessions, environment: PushEnvironment?, settings: @escaping @MainActor () async -> NotificationSettings) {
        self.environment = environment
        readSettings = settings
        // The sessions are main-actor isolated and publish from there.
        sessionObservation = sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        }
    }

    isolated deinit {
        settingsRead?.cancel()
    }

    /// Takes the device token APNs gave the app: call it from the app delegate's
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`. It is kept in memory
    /// only, and served only while a session is open.
    ///
    /// - Parameter deviceToken: The token, as the delegate method receives it.
    public func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        update(.registered(deviceToken: deviceToken.hexadecimal))
    }

    /// Takes why registering failed: call it from the app delegate's
    /// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    ///
    /// - Parameter error: The error, as the delegate method receives it.
    public func didFailToRegisterForRemoteNotifications(withError error: any Error) {
        update(.failed(message: error.localizedDescription))
    }

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case .refresh:
            if isServing {
                refreshSettings()
            }
        }
    }

    /// Whether a session is open that is served: the registration is then always there, if only
    /// as ``Registration/notRegistered``.
    private var isServing: Bool {
        snapshot.registration != nil
    }

    private func update(_ registration: Registration) {
        self.registration = registration
        if isServing {
            snapshot.registration = registration
        }
    }

    /// Serves everything as a session opens whose grant, if it has one, lists the capability,
    /// and nothing as it ends or expires.
    private func follow(_ state: DebugDrawerSessionState) {
        let session = state.session
        guard session?.id != snapshot.sessionID else { return }
        settingsRead?.cancel()
        guard let session, session.allows(Self.pluginID) else {
            snapshot = Snapshot(sessionID: session?.id, registration: nil, environment: nil, settings: nil)
            return
        }
        snapshot = Snapshot(sessionID: session.id, registration: registration, environment: environment, settings: nil)
        refreshSettings()
    }

    /// Reads the settings into the snapshot, unless the session has changed by the time they come.
    private func refreshSettings() {
        let sessionID = snapshot.sessionID
        settingsRead?.cancel()
        settingsRead = Task { [weak self, readSettings] in
            let settings = await readSettings()
            guard let self, !Task.isCancelled, isServing, snapshot.sessionID == sessionID else { return }
            snapshot.settings = settings
        }
    }
}
