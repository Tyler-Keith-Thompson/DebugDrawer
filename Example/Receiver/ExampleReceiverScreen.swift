import DebugDrawerLocalization
import DebugDrawerNetwork
import DebugDrawerReceiver
import SwiftUI

/// The host's one screen: a section per capability, each showing what the sidecar changes, with
/// the session indicator along the bottom while a session is open.
struct ExampleReceiverScreen: View {
    @ObservedObject var host: ExampleReceiverHost
    @ObservedObject var flags: ProductionFlags
    @ObservedObject var experiments: ProductionExperiments
    @ObservedObject var logging: ProductionLogging
    @ObservedObject var sessions: DebugDrawerSessions
    @ObservedObject var keeper: DebugDrawerBackgroundKeeper
    @ObservedObject var mocking: NetworkMocking
    @ObservedObject var diagnostics: DebugDrawerDiagnosticsCapture
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExampleReceiverSessionIndicator(sessions: sessions, keeper: keeper, keepRunning: host.keepRunningInBackground)
        }
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
