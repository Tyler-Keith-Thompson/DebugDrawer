import Combine
import CryptoKit
import DebugDrawerAccessibility
import DebugDrawerAnalytics
import DebugDrawerAppInfo
import DebugDrawerAppStateReset
import DebugDrawerHangDetector
import DebugDrawerLocalization
import DebugDrawerLocation
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
/// app hands its log lines and requests, the bug reports its Report a Bug trigger takes, the
/// push registration the app delegate hands the APNs device token, the scenarios a sidecar
/// launches it into, the actions a sidecar takes on its sign-in, the state a sidecar may reset, the
/// backends a sidecar may point it at for a session, the location a sidecar may spoof for one,
/// the settings keys a sidecar may edit, the hangs and signposts it records, and the read-only
/// snapshot of its state every sidecar report carries.
///
/// Everything here is in the release build too: a production app links the receiver and the
/// capability modules, never the drawer.
@MainActor
final class ExampleReceiverHost: ObservableObject {
    /// The request the Fetch Greeting button sends, which a sidecar's rule may answer.
    static let greetingURL = URL(string: "https://api.example.com/greeting")!
    // The literal is a valid URL, so the force unwrap can't fail.

    let flags: ProductionFlags
    /// The flag overrides a sidecar sets, which the app state lists.
    let flagOverrides: DebugDrawerFeatureFlagOverrides
    let experiments: ProductionExperiments
    /// The experiments a sidecar forces, whose buckets the app state lists.
    let experimentOverrides: DebugDrawerExperimentOverrides
    let logging: ProductionLogging
    /// The screens a sidecar's scenarios open.
    let scenarios = ProductionScenarios()
    /// The sign-in a sidecar's auth actions expire, refresh and end.
    let signIn: ProductionSignIn
    /// The defaults and caches a sidecar may reset.
    let appState: ProductionAppState
    /// The backends a sidecar's session points the app at: Production, Staging or Canary.
    let environments: ProductionEnvironments
    /// The store finder's location and fraud signal, which follow a sidecar's spoof.
    let location = ProductionLocation()
    /// What the store finder reads its location through, which a sidecar's session may spoof.
    let locationSpoofing: LocationSpoofing
    /// The settings keys a sidecar may read and edit for its session, and no other.
    let settings: DebugDrawerUserDefaults
    /// The freeze and the signposted load a sidecar's performance traces record.
    let performance: ProductionPerformance
    /// The build, the flag and experiment overrides, the backend, the signed-in user's hashed ID
    /// and two values of the app's own, served to a sidecar during its session and attached to
    /// every report it creates; also each bug report's state.
    let snapshot: DebugDrawerAppState
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
    /// Sessions of at most 15 minutes, opened only with a grant signed by the example's key.
    private static func sessions() -> DebugDrawerSessions {
        DebugDrawerSessions(
            maximumDuration: 15 * 60,
            grantPolicy: DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(ExampleGrantKey.publicKey)]),
                audience: Bundle.main.bundleIdentifier ?? "com.debugdrawer.example.receiver"
            )
        )
    }

    /// The app's session for its own API, listing the mocking protocol first so a sidecar's rules
    /// can answer it; `URLSession.shared` is never touched.
    private let apiSession: URLSession
    private var auditLogging: AnyCancellable?

    init() {
        let flags = ProductionFlags()
        let experiments = ProductionExperiments()
        let logging = ProductionLogging()
        let sessions = Self.sessions()
        let signIn = ProductionSignIn()
        let environments = ProductionEnvironments()
        let settings = ProductionSettings.model()
        let receiver = DebugDrawerReceiver(directory: ExampleSidecarStore.directory, sessions: sessions)
        let mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("api.example.com")])
        let diagnostics = DebugDrawerDiagnosticsCapture(sessions: sessions)
        // The models, not the adapters, so the app state reads the overrides they keep.
        let flagOverrides = DebugDrawerFeatureFlagOverrides(adapter: flags)
        let experimentOverrides = DebugDrawerExperimentOverrides(adapter: experiments)
        let snapshot = Self.snapshot(
            sessions: sessions, flagOverrides: flagOverrides, experimentOverrides: experimentOverrides,
            environments: environments.model, signIn: signIn
        )
        let bugReports = Self.bugReports(sessions: sessions, diagnostics: diagnostics, flags: flags, experiments: experiments, snapshot: snapshot)
        let pushRegistration = Self.pushRegistration(sessions: sessions)
        let appState = ProductionAppState(sessions: sessions)
        self.flags = flags
        self.flagOverrides = flagOverrides
        self.experiments = experiments
        self.experimentOverrides = experimentOverrides
        self.snapshot = snapshot
        self.signIn = signIn
        self.environments = environments
        locationSpoofing = LocationSpoofing(sessions: sessions, spoofingDidChange: location.spoofingDidChange)
        self.settings = settings
        self.logging = logging
        self.sessions = sessions
        self.receiver = receiver
        self.mocking = mocking
        self.diagnostics = diagnostics
        self.bugReports = bugReports
        self.pushRegistration = pushRegistration
        self.appState = appState
        performance = ProductionPerformance(sessions: sessions)
        keeper = DebugDrawerBackgroundKeeper(sessions: sessions)
        apiSession = Self.apiSession()
        enableCapabilities()
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

    /// Enables every capability the library ships on the receiver, before it starts.
    private func enableCapabilities() {
        receiver.enable(.featureFlagOverrides(flagOverrides))
        receiver.enable(.experimentOverrides(experimentOverrides))
        receiver.enable(.appState(snapshot))
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
        receiver.enable(.appStateReset(appState.requests))
        receiver.enable(.scenarios(scenarios.scenarios, launchURL: ProductionScenarios.launchURL))
        receiver.enable(.authActions(signIn.actions, launchURL: ProductionSignIn.launchURL))
        receiver.enable(.environments(environments.model))
        receiver.enable(.locationSpoofing(locationSpoofing))
        receiver.enable(.userDefaults(settings))
        receiver.enable(.performanceTraces(performance.traces))
    }

    /// The app's session for its own API, with the mocking protocol first in its protocols.
    private static func apiSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
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
    /// the checkout's flag and experiment, the greeting, the signed-in customer, whose email the
    /// redaction masks, and the app state as a sidecar sees it.
    private static func bugReports(
        sessions: DebugDrawerSessions,
        diagnostics: DebugDrawerDiagnosticsCapture,
        flags: ProductionFlags,
        experiments: ProductionExperiments,
        snapshot: DebugDrawerAppState
    ) -> DebugDrawerBugReports {
        DebugDrawerBugReports(sessions: sessions, diagnostics: diagnostics) {
            ExampleBugReportState(
                checkout: flags.value(forKey: "new-checkout") == .bool(true) ? "new" : "legacy",
                checkoutFlow: experiments.variant(forExperiment: "checkout-flow"),
                greeting: ProductionTweaks.greeting.value,
                customer: .init(email: "jane@example.com", plan: "pro"),
                appState: snapshot.read()
            )
        }
    }

    /// The app state a sidecar reads: the build's commit and branch (a CI script would write them
    /// into Info.plist), the flag and experiment overrides, the backend, the signed-in user's ID,
    /// hashed in the app, and two values of the app's own: the plan and the greeting. Nothing else
    /// is registered, and nothing secret: the access token stays in the sign-in.
    private static func snapshot(
        sessions: DebugDrawerSessions,
        flagOverrides: DebugDrawerFeatureFlagOverrides,
        experimentOverrides: DebugDrawerExperimentOverrides,
        environments: DebugDrawerEnvironments,
        signIn: ProductionSignIn
    ) -> DebugDrawerAppState {
        DebugDrawerAppState(
            sessions: sessions,
            buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "main"),
            featureFlags: flagOverrides,
            experiments: experimentOverrides,
            environments: environments,
            userID: { [weak signIn] in signIn?.userID },
            values: [
                DebugDrawerAppStateField("plan") { "pro" },
                DebugDrawerAppStateField("greeting") { .string(ProductionTweaks.greeting.value) }
            ]
        )
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
    let appState: DebugDrawerAppState.State
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
