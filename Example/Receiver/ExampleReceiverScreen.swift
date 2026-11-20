import DebugDrawerHangDetector
import DebugDrawerLocalization
import DebugDrawerNetwork
import DebugDrawerNotifications
import DebugDrawerReceiver
import SwiftUI

/// The host's one screen: a section per capability, each showing what the sidecar changes, with
/// the session indicator along the bottom while a session is open.
struct ExampleReceiverScreen: View {
    @ObservedObject var host: ExampleReceiverHost
    @ObservedObject var flags: ProductionFlags
    @ObservedObject var experiments: ProductionExperiments
    @ObservedObject var logging: ProductionLogging
    @ObservedObject var scenarios: ProductionScenarios
    @ObservedObject var signIn: ProductionSignIn
    @ObservedObject var appState: ProductionAppState
    @ObservedObject var sessions: DebugDrawerSessions
    @ObservedObject var keeper: DebugDrawerBackgroundKeeper
    @ObservedObject var mocking: NetworkMocking
    @ObservedObject var diagnostics: DebugDrawerDiagnosticsCapture
    @ObservedObject var backend: ProductionBackend
    @ObservedObject var environments: DebugDrawerEnvironments
    @ObservedObject var performance: ProductionPerformance
    @ObservedObject var traces: PerformanceTraces
    @State private var greeting = ProductionTweaks.greeting.value

    var body: some View {
        Form {
            Section("Sidecar") {
                LabeledContent("Store", value: host.storeSummary)
                if let serveError = host.serveError {
                    Text(serveError)
                        .foregroundStyle(.red)
                }
                Toggle("Sidecar Allowed", isOn: $host.isSidecarAllowed)
                    .accessibilityHint("Off, the receiver refuses every command and ends the session, like a remote kill switch")
            }
            Section {
                LabeledContent("Screen", value: scenarios.screen?.title ?? "Home")
                    .accessibilityIdentifier("ScenarioScreen")
            } header: {
                Text("Scenarios")
            } footer: {
                Text("A scenario the sidecar launches opens its screen here.")
            }
            Section {
                LabeledContent("Sign-In", value: signIn.state.title)
                    .accessibilityIdentifier("SignInState")
                if signIn.state == .signedOut {
                    Button("Sign In", action: signIn.signIn)
                        .accessibilityHint("Signs in again with a new fake token")
                }
            } header: {
                Text("Auth Actions")
            } footer: {
                Text("The sidecar expires, refreshes or ends the sign-in; it never sees the token.")
            }
            Section {
                LabeledContent("Seeded", value: appState.summary)
                    .accessibilityIdentifier("AppStateSeeded")
                Button("Seed Data", action: appState.seed)
                    .accessibilityHint("Writes defaults keys and cached thumbnails for a sidecar's reset to clear")
            } header: {
                Text("App State Reset")
            } footer: {
                Text("The sidecar may clear the app's UserDefaults and caches; the app clears what it confirms as it next comes to the foreground.")
            }
            Section {
                LabeledContent("Environment", value: environments.snapshot.activeTitle)
                    .accessibilityIdentifier("EnvironmentActive")
                LabeledContent("Base URL", value: backend.baseURL)
                    .accessibilityIdentifier("EnvironmentBaseURL")
            } header: {
                Text("Environment")
            } footer: {
                Text(
                    "A sidecar may switch to Staging or Canary for its session; the app is back on Production as it ends. "
                        + "The base URLs stay in the app."
                )
            }
            Section("Feature Flag Overrides") {
                LabeledContent("Checkout", value: flags.value(forKey: "new-checkout") == .bool(true) ? "New" : "Legacy")
                LabeledContent("Button Color", value: flags.value(forKey: "checkout-button-color")?.exampleDescription ?? "None")
            }
            Section("Experiment Overrides") {
                LabeledContent("Checkout Flow", value: experiments.variant(forExperiment: "checkout-flow") ?? "Not enrolled")
                LabeledContent("Onboarding", value: experiments.variant(forExperiment: "onboarding") ?? "Not enrolled")
                LabeledContent(
                    "Analytics",
                    value: experiments.analyticsExclusions.isEmpty
                        ? "Included"
                        : "Excluded from \(experiments.analyticsExclusions.joined(separator: ", "))"
                )
                .accessibilityIdentifier("ExperimentAnalyticsExclusion")
            }
            Section("Log Levels") {
                LabeledContent("Checkout", value: logging.level(of: ProductionLogging.checkout))
                LabeledContent("Sync", value: logging.level(of: ProductionLogging.sync))
                Button("Log Checkout Step") { logging.logCheckoutStep(customer: "jane@example.com") }
                    .accessibilityHint("Logs a line at each level; the checkout subsystem's level decides which are written")
                LabeledContent("Last Written", value: logging.lastWritten.isEmpty ? "Nothing yet" : logging.lastWritten.joined(separator: ", "))
                    .accessibilityIdentifier("LogLevelsLastWritten")
            }
            Section("Tweaks") {
                LabeledContent("Greeting", value: greeting)
                    .onReceive(ProductionTweaks.greeting.publisher) { greeting = $0 }
            }
            Section("Localization Review") {
                Text(LocalizationReview.shared.localizedString(forKey: "orders.title", value: "Orders"))
                Text(LocalizationReview.shared.localizedString(forKey: "orders.empty", value: "You have no orders yet."))
            }
            Section("Accessibility Overrides") {
                ExampleAccessibilityReadout()
            }
            Section("Analytics Events") {
                Button("Record Checkout Event", action: host.recordCheckoutEvent)
                    .accessibilityHint("Records checkout_tapped, which the sidecar sees while its session is open")
            }
            Section("Network Mocking") {
                Button("Fetch Greeting") {
                    Task { await host.fetchGreeting() }
                }
                .accessibilityHint("Requests api.example.com/greeting, which a sidecar's rule may answer")
                Text(host.greetingResponse)
                    .font(.footnote.monospaced())
                    .accessibilityLabel("Response: \(host.greetingResponse)")
                if mocking.snapshot.isActive {
                    Label("Network mocking active", systemImage: "network.badge.shield.half.filled")
                        .accessibilityIdentifier("NetworkMockingActive")
                }
            }
            Section("Diagnostics Capture") {
                Button("Log Sign-In", action: host.logSignIn)
                    .accessibilityHint("Logs a line with the customer's email, which a capturing sidecar sees redacted")
                LabeledContent(
                    "Captured",
                    value: diagnostics.snapshot.isCapturing
                        ? "\(diagnostics.snapshot.lines.count) lines, \(diagnostics.snapshot.requests.count) requests"
                        : "Not capturing"
                )
                .accessibilityIdentifier("DiagnosticsCaptured")
                if diagnostics.snapshot.isCapturing {
                    Label("Capturing diagnostics for a sidecar", systemImage: "record.circle")
                        .accessibilityIdentifier("DiagnosticsCaptureActive")
                }
            }
            Section {
                Button("Freeze for 2 s", action: performance.freeze)
                    .accessibilityHint("Keeps the main thread busy for two seconds: a hang a recording sidecar lists with its stack")
                Button("Load Report") {
                    Task { await performance.loadReport() }
                }
                .accessibilityHint("Loads a report marked as a signpost interval, which a recording sidecar lists with its duration")
                Text(performance.lastLoad)
                    .accessibilityIdentifier("PerformanceLastLoad")
                LabeledContent(
                    "Recorded",
                    value: traces.snapshot.isRecording
                        ? "\(traces.snapshot.stalls.count) stalls, \(traces.snapshot.intervals.count) intervals"
                        : "Not recording"
                )
                .accessibilityIdentifier("PerformanceTracesRecorded")
            } header: {
                Text("Performance Traces")
            } footer: {
                Text("While a sidecar records, the app watches its main thread; the recording is deleted as the session ends.")
            }
            Section("Bug Reports") {
                Button("Report a Bug", systemImage: "ladybug", action: host.reportBug)
                    .accessibilityHint("Takes a screenshot, the captured log lines and the app's state for the sidecar whose session is open")
                LabeledContent("Last Report", value: host.lastBugReport)
                    .accessibilityIdentifier("BugReportResult")
            }
            Section {
                LabeledContent("APNs", value: host.pushStatus)
                    .accessibilityIdentifier("PushRegistrationStatus")
                LabeledContent("Environment", value: host.pushRegistration.environment.map(\.summary) ?? "Not signed for push")
            } header: {
                Text("Push Registration")
            } footer: {
                Text("The sidecar sees the device token, the environment and the notification settings only during its session.")
            }
            Section {
                Button("Crash", role: .destructive) {
                    // A deliberate crash, for the person checking MetricKit forwarding.
                    fatalError("Crashed from the example's Crash button")
                }
                .accessibilityHint("Crashes the app; on the next launch MetricKit hands the receiver its crash diagnostic")
            } header: {
                Text("MetricKit Payloads")
            } footer: {
                Text(
                    "MetricKit hands the app its payloads on a device, a crash diagnostic on the launch after the crash; "
                        + "the sidecar lists them during its session."
                )
            }
        }
        .formStyle(.grouped)
        .sheet(item: $scenarios.screen) { screen in
            ExampleScenarioScreen(screen: screen) { scenarios.screen = nil }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExampleReceiverSessionIndicator(
                sessions: sessions, keeper: keeper, environments: environments, keepRunning: host.keepRunningInBackground
            )
        }
    }
}

/// The screen a scenario opened: its title and detail, and Done.
private struct ExampleScenarioScreen: View {
    let screen: ProductionScenarios.Screen
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(screen.title)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("ScenarioScreenTitle")
            Text(screen.detail)
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(minWidth: 320, minHeight: 240)
    }
}

/// The environment the accessibility overrides set, read back, so a change shows on the Mac too,
/// where text doesn't scale with Dynamic Type.
private struct ExampleAccessibilityReadout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LabeledContent("Dynamic Type", value: String(describing: dynamicTypeSize))
        LabeledContent("Contrast", value: contrast == .increased ? "Increased" : "Standard")
        LabeledContent("Reduce Motion", value: reduceMotion ? "On" : "Off")
    }
}

extension DebugDrawerFeatureFlagValue {
    /// The value as the screen shows it.
    fileprivate var exampleDescription: String {
        switch self {
        case let .bool(value): String(value)
        case let .number(value): value.formatted()
        case let .string(value): value
        }
    }
}

extension DebugDrawerEnvironments.Snapshot {
    /// The title of the environment the app is pointed at, as the screen and the indicator say it.
    var activeTitle: String {
        environments.first { $0.id == activeEnvironment }?.title ?? activeEnvironment
    }
}

extension PushEnvironment {
    /// The server and where the environment came from, as the screen says it.
    fileprivate var summary: String {
        let server = server == .production ? "Production" : "Sandbox"
        return switch source {
        case .host: "\(server) (stated by the app)"
        case .entitlement: "\(server) (entitlement)"
        case .provisioningProfile: "\(server) (provisioning profile)"
        case .appStoreDistribution: "\(server) (App Store build)"
        }
    }
}
