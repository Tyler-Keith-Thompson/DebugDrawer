import DebugDrawer
import DebugDrawerAccessibilityPlugin
import DebugDrawerAppInfoPlugin
import DebugDrawerConsolePlugin
import DebugDrawerDiskIOPlugin
import DebugDrawerEnergyPlugin
import DebugDrawerKeychainPlugin
import DebugDrawerNetworkPlugin
import DebugDrawerPerformancePlugin
import DebugDrawerScreenshotPlugin
import DebugDrawerUserDefaultsPlugin
import DebugDrawerViewInspectorPlugin
import DebugDrawerLocationPlugin
import DebugDrawerLoadedLibrariesPlugin
import DebugDrawerDeepLinkPlugin
import DebugDrawerCookiesPlugin
import DebugDrawerLaunchTimePlugin
import DebugDrawerTweaksPlugin
import DebugDrawerFeatureFlagsPlugin
import DebugDrawerCrashReportsPlugin
import DebugDrawerHangDetectorPlugin
import DebugDrawerLeakDetectorPlugin
import DebugDrawerMetricKitPlugin
import DebugDrawerPermissionsPlugin
import DebugDrawerNotificationsPlugin
import DebugDrawerBackgroundTasksPlugin
import DebugDrawerAnalyticsPlugin
import DebugDrawerLocalizationPlugin
import DebugDrawerScreenRecordingPlugin
import DebugDrawerDesignOverlayPlugin
import DebugDrawerColorVisionPlugin
import DebugDrawerAppStateResetPlugin
import SwiftUI

/// Demonstrates Send Report without a server: "sends" each report by copying it into the app's
/// Caches/Sent Reports folder.
struct FolderReportUploader: DebugDrawerReportUploader {
    func upload(_ archive: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = URL.cachesDirectory.appending(path: "Sent Reports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        progress(0.5)
        let destination = folder.appending(path: archive.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: archive, to: destination)
        progress(1)
    }
}

@main
struct DebugDrawerExampleiOSApp: App {
    // Registers for remote notifications and forwards the token to the Notifications plugin.
    // `bazel build //...` also compiles this app for the Mac, where UIKit doesn't exist.
    #if canImport(UIKit)
        @UIApplicationDelegateAdaptor(ExampleAppDelegate.self) private var appDelegate
    #endif

    init() {
        // First, so a crash in the rest of startup is recorded. It compiles in release, where it
        // installs nothing; launched with -CrashOnLaunch, the app crashes right after it.
        CrashReports.install()
        // Next, before the first string is looked up, so the lookups at launch are recorded. It
        // compiles in release too, where it does nothing; launched with -PseudoLocalize or
        // -ShowLocalizationKeys, the app starts in that mode.
        ExampleLocalization.install()
        if ProcessInfo.processInfo.arguments.contains(ExampleCrash.launchArgument) {
            ExampleCrash.crash()
        }
        // Compiles in release too, where it starts nothing; launched with -HangOnLaunch, the app
        // blocks its main thread for 500 ms once it first goes idle.
        HangDetector.install()
        if ProcessInfo.processInfo.arguments.contains(ExampleHang.launchArgument) {
            ExampleHang.blockAfterLaunch()
        }
        // Compiles in release too, where it does nothing; launched with -LeakOnLaunch, the app
        // presents and dismisses a screen without a leak and one with a retain cycle once it first
        // goes idle.
        LeakDetector.install()
        if ProcessInfo.processInfo.arguments.contains(ExampleLeak.launchArgument) {
            ExampleLeak.presentAndDismissAfterLaunch()
        }
        // Compiles in release too, where it does nothing; launched with -AddSampleMetricKitPayloads,
        // the app adds a sample metric payload and a sample diagnostic payload.
        MetricKitPayloads.install()
        if ProcessInfo.processInfo.arguments.contains(ExampleMetricKit.launchArgument) {
            ExampleMetricKit.addSamples()
        }
        // Compiles in release too, where it does nothing and references no permission framework.
        // The Info.plist declares a few usage descriptions, so the plugin has rows to show.
        PrivacyPermissions.install()
        // Compiles in release too, where it does nothing. The app delegate forwards the device
        // token.
        PushNotifications.install()
        // Compiles in release too, where it does nothing. The Info.plist permits two task
        // identifiers, whose launch handlers the app delegate registers.
        BackgroundTaskRequests.install()
        // Compiles in release too, where it does nothing and records nothing. The counter's
        // buttons and Track Sample Event record events; launched with -TrackSampleAnalyticsEvents,
        // the app records one of each sample at startup.
        AnalyticsEvents.install()
        if ProcessInfo.processInfo.arguments.contains(ExampleAnalytics.launchArgument) {
            ExampleAnalytics.trackAllSamples()
        }
        // Installs the Databases plugin, which compiles in release too and does nothing there;
        // launched with -SeedSampleDatabase, the app first writes its sample stores.
        ExampleDatabase.install()
        // Installs Screen Recording, which compiles in release too and does nothing there; launched
        // with -PinScreenRecordingToHUD, the app pins its Record button to the HUD.
        ExampleScreenRecording.install()
        // Installs Design Overlay, which compiles in release too and does nothing there; launched
        // with -DesignOverlaySample, the app shows a generated sample comp over itself and pins the
        // plugin to the HUD.
        ExampleDesignOverlay.install()
        // Installs Color Vision, which compiles in release too and does nothing there; launched with
        // -ColorVision and a simulation's name (protanopia, deuteranopia, tritanopia or grayscale),
        // the app starts in that simulation.
        ExampleColorVision.install()
        // Installs Reset App State, which compiles in release too and does nothing there; launched with
        // -SeedResettableState, the app first writes state of every kind for it to clear.
        ExampleAppStateReset.install()
        // Launched with -SeedKeychain, adds a password in each of the example's access groups and
        // a private key, for the Keychain plugin to list.
        ExampleKeychain.install()
        // Installs UserDefaults over the standard defaults and an app group's suite, seeded with a
        // value of each type; it compiles in release too and does nothing there.
        ExampleUserDefaults.install()
        // Installs File Browser, which compiles in release too and does nothing there; launched
        // with -SeedSampleFiles, the app first writes sample files to preview.
        ExampleFileBrowser.install()
        // Installs Network; launched with -SeedNetworkMock, it adds mocks that answer the
        // Fetch Greeting and Place Order buttons, and with -SeedNetworkCondition, a profile that
        // slows example.com.
        ExampleNetwork.install()
        // Launched with -WebSocketEchoServer, starts a WebSocket echo server on 127.0.0.1 for the
        // WebSocket buttons.
        ExampleWebSocketServer.startIfAsked()
        installShippedPlugins()
    }

    /// The plugins installed with one call each, inside `#if DEBUG`; a function of its own to keep
    /// launch short enough to read.
    private func installShippedPlugins() {
        #if DEBUG
            ExampleConsole.install()
            DebugDrawer.shared.installDiskIO()
            DebugDrawer.shared.installViewInspector()
            DebugDrawer.shared.installAccessibility()
            DebugDrawer.shared.installPerformance()
            DebugDrawer.shared.installEnergy()
            DebugDrawer.shared.installScreenshot()
            DebugDrawer.shared.installAppInfo()
            DebugDrawer.shared.installKeychain()
            DebugDrawer.shared.installLocation()
            DebugDrawer.shared.installLoadedLibraries()
            DebugDrawer.shared.installDeepLink()
            DebugDrawer.shared.installCookies()
            DebugDrawer.shared.installLaunchTime()
            ExampleTweaks.install()
            ExampleFeatureFlags.install()
            DebugDrawer.shared.reportUploader = FolderReportUploader()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ExampleContentView_iOS()
                // Redraws the app's own strings when a Localization mode changes; beneath
                // .debugDrawer(), so the drawer keeps its place.
                .debugLocalization()
                .debugAccessibilityOverrides()
                // The design comp over the app, beneath .debugDrawer(), so the drawer stays above it.
                .debugDesignOverlay()
                .debugGrid()
                .debugDrawer()
                // Launched with -OpenDebugDrawer, the window opens with the drawer open, so it can
                // be checked without a hand, in the simulator or as a Mac Catalyst app.
                .onAppear {
                    #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
                            DebugDrawer.shared.toggle()
                        }
                    #endif
                }
                .background {
                    Button("") {
                        // The drawer exists in debug builds only.
                        #if DEBUG
                            DebugDrawer.shared.toggle()
                        #endif
                    }
                        .keyboardShortcut("d", modifiers: .control)
                        .hidden()
                }
        }
    }
}

struct ExampleContentView_iOS: View {
    // Kept in the defaults, so the Tweaks plugin's Reset counter action can clear it.
    @AppStorage(ExampleTweaks.counterKey) private var counter = 0
    @State private var text = ""
    @State private var isShowingSheet = false

    var body: some View {
        NavigationStack {
            List {
                // The screen's content is under the Color Vision simulation, a section's rows at a
                // time: the List around them is UIKit's, which a shader can't draw. The Inputs
                // section stays outside it, and the stepper's control too (ExampleLocalizedSection):
                // UIKit draws them, so they would show SwiftUI's placeholder.

                // First, so its strings show beside the drawer.
                ExampleLocalizedSection()

                Section("Controls") {
                    HStack {
                        Button("Increment") {
                            counter += ExampleTweaks.counterStep.value
                            ExampleAnalytics.trackCounter("increment", value: counter)
                        }
                        Button("Print") { ExampleConsole.log("Counter: \(counter)") }
                        Button("Reset") {
                            counter = 0
                            ExampleAnalytics.trackCounter("reset", value: counter)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Show Sheet") {
                        isShowingSheet = true
                        ExampleAnalytics.track("sheet_shown")
                    }
                    // Analytics lists each event as it is recorded. Recording does nothing in
                    // release, so neither does the button.
                    #if DEBUG
                        Button("Track Sample Event") { ExampleAnalytics.trackSample() }
                    #endif
                    // Keychain lists both passwords, each in its access group, and the key.
                    Button("Add Sample Keychain Items") { ExampleKeychain.seed() }
                    // Crash Reports shows the crash on the next launch.
                    Button("Crash the App", role: .destructive) { ExampleCrash.crash() }
                    // Hangs reports the stall with its stack and a toast.
                    Button("Block the Main Thread for 500 ms") { ExampleHang.blockMainThread() }
                    // Leaks flags the screen once it is dismissed, with a toast.
                    Button("Open a Leaking Screen") { ExampleLeak.presentLeakingScreen() }
                    // MetricKit lists the samples, clearly named as such: MetricKit itself delivers nothing
                    // to a debug run in time to see. Adding does nothing in release, so neither does the button.
                    #if DEBUG
                        Button("Add Sample MetricKit Payloads") { ExampleMetricKit.addSamples() }
                    #endif

                    Text("Counter: \(counter)")
                        .font(.title2.monospacedDigit())
                        .accessibilityAddTraits(.isHeader)

                    ExampleTweaksBanner()
                    ExampleFeatureFlagsSummary()
                    ExampleResettableState()
                    // UserDefaults lists the key as it is written, without a reload.
                    ExampleUserDefaultsWriter()
                }
                .debugColorVision()

                // Network logs each request; a mock answers the greeting, which no server does.
                Section("Network") {
                    ExampleNetworkRequests()
                    ExampleWebSocketDemo()
                }

                // Colors the Color Vision plugin simulates.
                Section("Colors") {
                    ExampleColorSwatches()
                }
                .debugColorVision()

                Section("Inputs") {
                    TextField("Sample text field", text: $text)
                        .accessibilityLabel("Sample text")
                    Slider(value: .constant(0.5))
                        .accessibilityLabel("Sample slider")
                    Toggle("Toggle", isOn: .constant(true))
                }

                Section("Items") {
                    ForEach(1 ... 20, id: \.self) { item in
                        Label("Item \(item)", systemImage: "circle.fill")
                    }
                }
                .debugColorVision()
            }
            .navigationTitle("DebugDrawer Example")
            .sheet(isPresented: $isShowingSheet) {
                ExampleSheet_iOS()
            }
            .toolbar {
                // The drawer exists in debug builds only. A device without a keyboard has no
                // Ctrl+D, so the example opens it from here.
                #if DEBUG
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            DebugDrawer.shared.toggle()
                        } label: {
                            Label("Debug Drawer", systemImage: "ladybug")
                        }
                    }
                    // Shows what a plugin's notice looks like: a badge on Network and a toast that opens it.
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            let network = NetworkPlugin()
                            network.setBadge(1)
                            network.postToast("GET /api/orders failed with 500")
                        } label: {
                            Label("Post Sample Notice", systemImage: "bell.badge")
                        }
                    }
                #endif
            }
        }
    }
}

/// A presented sheet with a drawer of its own, as a host adds one to each sheet's root: opened
/// over the sheet, the drawer's capture includes it.
struct ExampleSheet_iOS: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Sample Sheet")
                .font(.largeTitle)
                .navigationTitle("Sheet")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    #if DEBUG
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                DebugDrawer.shared.toggle()
                            } label: {
                                Label("Debug Drawer", systemImage: "ladybug")
                            }
                        }
                    #endif
                }
        }
        .debugDrawer()
    }
}
