import DebugDrawerViewInspectorPlugin
import SwiftUI

/// The macOS example's main screen: the counter, the plugins' sample rows and the controls they act
/// on. The test bench, in the sidebar, has an action for each plugin besides.
struct ExampleMainScreen: View {
    // Kept in the defaults, so the Tweaks plugin's Reset counter action can clear it.
    @AppStorage(ExampleTweaks.counterKey) private var counter = 0

    var body: some View {
        VStack(spacing: 20) {
            // The screen's content, under the Color Vision simulation. The inputs below stay
            // outside it, and the stepper's control too (ExampleLocalizedStrings): AppKit draws
            // them, and a shader can't, so they would show SwiftUI's placeholder.
            Group {
                Text("DebugDrawer Example")
                    .font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)

                Text("Press Ctrl+D to open the debug drawer")
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 16) {
                    Button("Increment") {
                        counter += ExampleTweaks.counterStep.value
                        ExampleAnalytics.trackCounter("increment", value: counter)
                    }
                    Button("Print") { print("Counter: \(counter)") }
                    Button("Log") { ExampleConsole.logSubsystems(counter) }
                        .accessibilityLabel("Log from Two Subsystems")
                    // The app's own logger reaches the Console through ConsoleLogSink, with metadata.
                    Button("App Logger") { ExampleLogger.logPaymentDeclined(counter) }
                        .accessibilityHint("Logs a declined payment, with metadata, through the app's own logger")
                    Button("Reset") {
                        counter = 0
                        ExampleAnalytics.trackCounter("reset", value: counter)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Counter actions")

                // The drawer opens above each of these (Ctrl+D or the Debug menu while one is up).
                ExamplePresentationButtons()

                Text("Counter: \(counter)")
                    .font(.title2.monospacedDigit())
                    .accessibilityAddTraits(.isHeader)

                ExampleTweaksBanner()
                ExampleFeatureFlagsSummary()
                ExampleResettableState()
                // UserDefaults lists the key as it is written, without a reload.
                ExampleUserDefaultsWriter()
                // The app's own location manager: the Location plugin's spoofed coordinate or
                // route reaches it.
                ExampleLocationReadout()
                // Network logs each request; a mock answers the greeting, which no server does.
                ExampleNetworkRequests()
                ExampleWebSocketDemo()
                    .frame(maxWidth: 480)
                // The Deep Link Tester's universal links and activities, as the app receives them.
                ExampleDeepLinkRow()
                    .frame(maxWidth: 480)

            }
            .debugColorVision()

            ExampleLocalizedStrings()

            Group {
                // Colors the Color Vision plugin simulates.
                ExampleColorSwatches()
                    .frame(maxWidth: 480)

                // Crash Reports shows the crash on the next launch.
                Button("Crash the App", role: .destructive) { ExampleCrash.crash() }
                // Hangs reports the stall with its stack and a toast.
                Button("Block the Main Thread for 500 ms") { ExampleHang.blockMainThread() }
                // Performance lists the busy thread at the top of its Threads.
                ExampleBusyThreadRow()
                // Leaks flags the sheet once it is closed, with a toast.
                Button("Open a Leaking Screen") { ExampleLeak.presentLeakingScreen() }
                // MetricKit lists the samples, clearly named as such: MetricKit itself delivers nothing
                // to a debug run in time to see. Adding does nothing in release, so neither does the button.
                Button("Add Sample MetricKit Payloads") { ExampleMetricKit.addSamples() }
                // Analytics lists each event as it is recorded. Recording does nothing in release,
                // so neither does the button.
                Button("Track Sample Event") { ExampleAnalytics.trackSample() }
                // File Browser lists them under Documents/Samples; Databases lists the SQLite shop
                // and the Core Data pets, each written afresh.
                HStack {
                    Button("Create Sample Files") { ExampleFileBrowser.seed() }
                    Button("Write Sample Databases") { ExampleDatabase.seed() }
                }
            }
            .debugColorVision()

            HStack {
                TextField("Sample text field", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .accessibilityLabel("Sample text")

                Slider(value: .constant(0.5))
                    .frame(width: 150)
                    .accessibilityLabel("Sample slider")

                Toggle("Toggle", isOn: .constant(true))
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Listed in the View Inspector's SwiftUI Renders: it renders again when the counter changes.
        .trackRenders("ExampleMainScreen")
    }
}
