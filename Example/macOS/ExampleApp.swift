import AppKit
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
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
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
        // Compiles in release too, where it does nothing. The delegate methods below forward the
        // device token, or why registering failed.
        PushNotifications.install()
        ExamplePushNotifications.register()
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

        setupMenuBar()
        createMainWindow()
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

    func application(_: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }

    func application(_: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushNotifications.didFailToRegisterForRemoteNotifications(withError: error)
    }

    private func createMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DebugDrawer Example"
        window.contentViewController = NSHostingController(rootView: ExampleContentView())
        window.setFrameAutosaveName("DebugDrawerExample")
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // The drawer exists in debug builds only. A menu item, unlike a hidden button, is listed
        // in the menu bar and reachable through accessibility.
        #if DEBUG
            let debugMenuItem = NSMenuItem()
            let debugMenu = NSMenu(title: "Debug")
            let toggle = debugMenu.addItem(
                withTitle: "Toggle Debug Drawer",
                action: #selector(toggleDebugDrawer),
                keyEquivalent: "d"
            )
            toggle.keyEquivalentModifierMask = .control
            toggle.target = self
            let notice = debugMenu.addItem(
                withTitle: "Post Sample Notice",
                action: #selector(postSampleNotice),
                keyEquivalent: ""
            )
            notice.target = self
            debugMenuItem.submenu = debugMenu
            mainMenu.addItem(debugMenuItem)
        #endif

        NSApp.mainMenu = mainMenu
    }

    #if DEBUG
        @objc private func toggleDebugDrawer() {
            DebugDrawer.shared.toggle()
        }

        // Shows what a plugin's notice looks like: a badge on Network and a toast that opens it.
        @objc private func postSampleNotice() {
            let network = NetworkPlugin()
            network.setBadge(1)
            network.postToast("GET /api/orders failed with 500")
        }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

// MARK: - Example content

struct ExampleContentView: View {
    @State private var selectedItem: String?
    // Kept in the defaults, so the Tweaks plugin's Reset counter action can clear it.
    @AppStorage(ExampleTweaks.counterKey) private var counter = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("Views") {
                    ForEach(["Buttons", "Text Fields", "Sliders", "Toggles", "Images"], id: \.self) { item in
                        Text(item)
                    }
                }
                Section("Data") {
                    ForEach(["Table", "Grid", "Chart", "List"], id: \.self) { item in
                        Text(item)
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
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
                        Button("Reset") {
                            counter = 0
                            ExampleAnalytics.trackCounter("reset", value: counter)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Counter actions")

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
                    // Leaks flags the sheet once it is closed, with a toast.
                    Button("Open a Leaking Screen") { ExampleLeak.presentLeakingScreen() }
                    // MetricKit lists the samples, clearly named as such: MetricKit itself delivers nothing
                    // to a debug run in time to see. Adding does nothing in release, so neither does the button.
                    #if DEBUG
                        Button("Add Sample MetricKit Payloads") { ExampleMetricKit.addSamples() }
                    #endif
                    // Analytics lists each event as it is recorded. Recording does nothing in release,
                    // so neither does the button.
                    #if DEBUG
                        Button("Track Sample Event") { ExampleAnalytics.trackSample() }
                    #endif
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
        }
        // Redraws the app's own strings when a Localization mode changes; beneath .debugDrawer(),
        // so the drawer keeps its place.
        .debugLocalization()
        .debugAccessibilityOverrides()
        // The design comp over the app, beneath .debugDrawer(), so the drawer stays above it.
        .debugDesignOverlay()
        .debugGrid()
        .debugDrawer()
        // Launched with -OpenDebugDrawer, the window opens with the drawer open, so it can be
        // checked without a hand, like the iOS example.
        .onAppear {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
                    DebugDrawer.shared.toggle()
                }
            #endif
        }
    }
}
