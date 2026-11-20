import Combine
import CryptoKit
import DebugDrawerAccessibility
import DebugDrawerAnalytics
import DebugDrawerLocalization
import DebugDrawerMetricKit
import DebugDrawerNetwork
import DebugDrawerNotifications
import DebugDrawerReceiver
import DebugDrawerTweaks
import ExampleSidecarStore
import Foundation
import os

/// The production host's side of the sidecar, made once at launch: the receiver serving every
/// capability the library ships, sessions that need a grant signed by the example's grant server
/// (Example/Sidecar's stand-in for a company's), the keeper that holds the app running while a
/// session is open, the session whose requests a sidecar may mock, the diagnostics capture the
/// app hands its log lines and requests, the bug reports its Report a Bug trigger takes, and the
/// push registration the app delegate hands the APNs device token.
///
/// Everything here is in the release build too: a production app links the receiver and the
/// capability modules, never the drawer.
@MainActor
final class ExampleReceiverHost: ObservableObject {
    /// The request the Fetch Greeting button sends, which a sidecar's rule may answer.
    static let greetingURL = URL(string: "https://api.example.com/greeting")!
    // The literal is a valid URL, so the force unwrap can't fail.

    let flags: ProductionFlags
    let experiments: ProductionExperiments
    let logging: ProductionLogging
    let sessions: DebugDrawerSessions
    /// Keeps the app running while a session is open: a background task on iOS, an App Nap
    /// activity on the Mac.
    let keeper: DebugDrawerBackgroundKeeper
    let mocking: NetworkMocking
    /// What the app logs and sends, captured for a sidecar that starts it in its session.
    let diagnostics: DebugDrawerDiagnosticsCapture
    /// The bug reports Report a Bug takes during a sidecar's session, with the diagnostics
    /// capture's recent lines and the app's state.
    let bugReports: DebugDrawerBugReports
    /// What the last Report a Bug came to.
    @Published private(set) var lastBugReport = "None taken"
    /// The APNs device token, push environment and notification settings, served to a sidecar
    /// during its session so an employee can aim a test push at this device.
    let pushRegistration: PushRegistrationMirror
    /// What APNs answered as the app registered, as the screen says it: never the token itself.
    @Published private(set) var pushStatus = "Registering…"
    /// Where the store is, as the screen says it.
    let storeSummary = ExampleSidecarStore.summary
    /// Why the receiver isn't serving, when it isn't.
    @Published private(set) var serveError: String?
    /// What the last Fetch Greeting got.
    @Published private(set) var greetingResponse = "Not fetched yet"
    /// The host's kill switch, standing in for a remote configuration value: off, the receiver
    /// serves nothing, refuses everything and ends the open session.
    @Published var isSidecarAllowed = true {
        didSet {
            let isAllowed = isSidecarAllowed
            receiver.isAllowed = { isAllowed }
        }
    }

    private static let logger = Logger(subsystem: "com.debugdrawer.example.receiver", category: "Sidecar")
    private let receiver: DebugDrawerReceiver
    /// The app's session for its own API, listing the mocking protocol first so a sidecar's rules
    /// can answer it; `URLSession.shared` is never touched.
    private let apiSession: URLSession
    private var auditLogging: AnyCancellable?

    init() {
        let flags = ProductionFlags()
        let experiments = ProductionExperiments()
        let logging = ProductionLogging()
        let sessions = DebugDrawerSessions(
            maximumDuration: 15 * 60,
            grantPolicy: DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(ExampleGrantKey.publicKey)]),
                audience: Bundle.main.bundleIdentifier ?? "com.debugdrawer.example.receiver"
            )
        )
        let receiver = DebugDrawerReceiver(directory: ExampleSidecarStore.directory, sessions: sessions)
        let mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("api.example.com")])
        let diagnostics = DebugDrawerDiagnosticsCapture(sessions: sessions)
        let bugReports = Self.bugReports(sessions: sessions, diagnostics: diagnostics, flags: flags, experiments: experiments)
        let pushRegistration = Self.pushRegistration(sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        receiver.enable(.experimentOverrides(experiments))
        receiver.enable(.logLevels(logging))
        receiver.enable(.tweaks(ProductionTweaks.greeting, ProductionTweaks.diagnostics))
        receiver.enable(.localizationReview())
        receiver.enable(.accessibilityEnvironmentOverrides())
        receiver.enable(.analyticsEvents(sessions: sessions))
        receiver.enable(.metricKitPayloads(sessions: sessions))
        receiver.enable(.networkMocking(mocking))
        receiver.enable(.diagnosticsCapture(diagnostics))
        receiver.enable(.bugReports(bugReports))
        receiver.enable(.pushRegistration(pushRegistration))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
        self.flags = flags
        self.experiments = experiments
        self.logging = logging
        self.sessions = sessions
        self.receiver = receiver
        self.mocking = mocking
        self.diagnostics = diagnostics
        self.bugReports = bugReports
        self.pushRegistration = pushRegistration
        keeper = DebugDrawerBackgroundKeeper(sessions: sessions)
        apiSession = URLSession(configuration: configuration)
        // The audit log goes to the app's own log, as a host would forward it to its own.
        auditLogging = sessions.auditEntries.sink { entry in
            Self.logger.notice("Audit: \(entry.capability, privacy: .public) \(String(describing: entry.event), privacy: .public)")
        }
        do {
            try receiver.start()
            Self.logger.notice("Serving a sidecar at \(ExampleSidecarStore.directory.path, privacy: .public)")
        } catch {
            serveError = "No sidecar can reach the app: \(error)"
            Self.logger.error("The receiver didn't start: \(String(describing: error), privacy: .public)")
        }
    }

    /// Sends the app's own request, which a sidecar's rule answers during its session; without
    /// one it goes to the network, where api.example.com doesn't answer.
    ///
    /// The request and its outcome go to the diagnostics capture, which keeps them, the token
    /// redacted, while a sidecar captures.
    func fetchGreeting() async {
        greetingResponse = "Fetching…"
        var request = URLRequest(url: Self.greetingURL)
        request.setValue("Bearer example-token", forHTTPHeaderField: "Authorization")
        let started = Date()
        do {
            let (data, response) = try await apiSession.data(for: request)
            diagnostics.record(request, response: response, body: data, started: started)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            greetingResponse = "\(status): \(String(bytes: data, encoding: .utf8) ?? "\(data.count) bytes")"
        } catch {
            diagnostics.record(request, error: error, started: started)
            greetingResponse = "Failed: \(error.localizedDescription)"
        }
    }

    /// Logs a sign-in as the app's logger would, to os_log and, through the logger's backend, to
    /// the diagnostics capture, which keeps it with the email address redacted while a sidecar
    /// captures.
    func logSignIn() {
        let customer = "jane@example.com"
        Self.logger.notice("Signed in \(customer, privacy: .private)")
        diagnostics.log(
            level: .notice, message: "Signed in \(customer)", metadata: ["screen": "checkout", "session_id": "s-1042"],
            subsystem: "com.debugdrawer.example.receiver", category: "Account"
        )
    }

    /// The bug reports Report a Bug takes. The state a report carries is the host's choice: here
    /// the checkout's flag and experiment, the greeting, and the signed-in customer, whose email the
    /// redaction masks.
    private static func bugReports(
        sessions: DebugDrawerSessions, diagnostics: DebugDrawerDiagnosticsCapture, flags: ProductionFlags, experiments: ProductionExperiments
    ) -> DebugDrawerBugReports {
        DebugDrawerBugReports(sessions: sessions, diagnostics: diagnostics) {
            ExampleBugReportState(
                checkout: flags.value(forKey: "new-checkout") == .bool(true) ? "new" : "legacy",
                checkoutFlow: experiments.variant(forExperiment: "checkout-flow"),
                greeting: ProductionTweaks.greeting.value,
                customer: .init(email: "jane@example.com", plan: "pro")
            )
        }
    }

    /// The push registration the app delegate hands the device token, serving the environment the
    /// app is signed for, read from its signature or embedded profile. A simulator build and the
    /// Mac example, signed ad hoc, carry neither, so the host states the sandbox, which a
    /// development build's token belongs to, and the sidecar shows it as the host's.
    private static func pushRegistration(sessions: DebugDrawerSessions) -> PushRegistrationMirror {
        PushRegistrationMirror(sessions: sessions, environment: PushEnvironment.detected() ?? PushEnvironment(server: .sandbox, source: .host))
    }

    /// Takes a bug report for the sidecar whose session is open: the app's own trigger, a button
    /// and a menu item here, as DebugDrawer adds none. Outside a session it takes nothing.
    func reportBug() {
        switch bugReports.trigger(note: "Reported from the example's Report a Bug") {
        case .captured:
            lastBugReport = "Taken: the sidecar shows it under Bug Reports"
        case .refused(.noActiveSession):
            lastBugReport = "Nothing taken: no sidecar session is open"
        case let .refused(reason):
            lastBugReport = "Refused: \(reason.rawValue)"
        }
    }

    /// Hands the push registration capability the token APNs gave the app, from the app delegate.
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        pushRegistration.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        pushStatus = "Registered: a sidecar sees the token during its session"
    }

    /// Hands the push registration capability why registering failed, from the app delegate.
    func didFailToRegisterForRemoteNotifications(withError error: any Error) {
        pushRegistration.didFailToRegisterForRemoteNotifications(withError: error)
        pushStatus = "Failed: \(error.localizedDescription)"
    }

    /// Records an analytics event as the app hands it to its analytics service: mirrored, with
    /// the email redacted, to a sidecar whose session is open.
    func recordCheckoutEvent() {
        AnalyticsEvents.record(
            "checkout_tapped",
            properties: ["plan": "pro", "seats": 3, "email": "jane@example.com"],
            source: "Example Analytics"
        )
    }

    /// Keeps the app running for the open session: on iOS 26 and later, a continued processing
    /// task the system shows with the session's progress; elsewhere the platform's short request
    /// the keeper already holds. A person's action, before they switch to the sidecar.
    func keepRunningInBackground() {
        keeper.startSession(duration: sessions.maximumDuration, title: "Debug session", subtitle: "The example sidecar is connected")
    }
}

/// The app's state as a bug report carries it, chosen by the host.
struct ExampleBugReportState: Encodable {
    struct Customer: Encodable {
        let email: String
        let plan: String
    }

    let checkout: String
    let checkoutFlow: String?
    let greeting: String
    let customer: Customer
}

/// The public key of the example's grant server, which signs every grant the example sidecar
/// sends: RFC 8037's Ed25519 test key, published, so it signs nothing a real app trusts. A company
/// embeds its own server's key.
enum ExampleGrantKey {
    static let publicKey: Curve25519.Signing.PublicKey = {
        // The literal is 32 bytes of valid base64, an Ed25519 public key, so neither step fails.
        do {
            return try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=")!)
        } catch {
            preconditionFailure("The example's grant key doesn't decode: \(error)")
        }
    }()
}
