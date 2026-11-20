import Combine
import CryptoKit
import DebugDrawerAccessibility
import DebugDrawerAnalytics
import DebugDrawerLocalization
import DebugDrawerMetricKit
import DebugDrawerNetwork
import DebugDrawerReceiver
import DebugDrawerTweaks
import ExampleSidecarStore
import Foundation
import os

/// The production host's side of the sidecar, made once at launch: the receiver serving every
/// capability the library ships, sessions that need a grant signed by the example's grant server
/// (Example/Sidecar's stand-in for a company's), the keeper that holds the app running while a
/// session is open, and the session whose requests a sidecar may mock.
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
    let sessions: DebugDrawerSessions
    /// Keeps the app running while a session is open: a background task on iOS, an App Nap
    /// activity on the Mac.
    let keeper: DebugDrawerBackgroundKeeper
    let mocking: NetworkMocking
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
        let sessions = DebugDrawerSessions(
            maximumDuration: 15 * 60,
            grantPolicy: DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(ExampleGrantKey.publicKey)]),
                audience: Bundle.main.bundleIdentifier ?? "com.debugdrawer.example.receiver"
            )
        )
        let receiver = DebugDrawerReceiver(directory: ExampleSidecarStore.directory, sessions: sessions)
        let mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("api.example.com")])
        receiver.enable(.featureFlagOverrides(flags))
        receiver.enable(.experimentOverrides(experiments))
        receiver.enable(.tweaks(ProductionTweaks.greeting, ProductionTweaks.diagnostics))
        receiver.enable(.localizationReview())
        receiver.enable(.accessibilityEnvironmentOverrides())
        receiver.enable(.analyticsEvents(sessions: sessions))
        receiver.enable(.metricKitPayloads(sessions: sessions))
        receiver.enable(.networkMocking(mocking))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
        self.flags = flags
        self.experiments = experiments
        self.sessions = sessions
        self.receiver = receiver
        self.mocking = mocking
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
    func fetchGreeting() async {
        greetingResponse = "Fetching…"
        do {
            let (data, response) = try await apiSession.data(from: Self.greetingURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            greetingResponse = "\(status): \(String(bytes: data, encoding: .utf8) ?? "\(data.count) bytes")"
        } catch {
            greetingResponse = "Failed: \(error.localizedDescription)"
        }
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
