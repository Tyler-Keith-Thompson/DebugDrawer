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
import ExampleTestBench
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
    private var appKitWindow: ExampleAppKitWindowController?
    /// The windows opened with Debug > New Window (or -NewWindow).
    private let windows = ExampleWindows()
    /// The remote viewer, opened with Debug > Remote Viewer (or -OpenRemoteViewer).
    private let remoteWindow = ExampleRemoteWindow()

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
        // Installs the Deep Link Tester with a handler that records each activity, shown in the
        // window as the last continued activity.
        ExampleDeepLink.install()
        installShippedPlugins()
        // Lists Remote Viewing in the drawer, which serves the Console and Network to a viewer on
        // another device (this app's Remote window, say) once started; launched with
        // -ServeRemoteViewers, it starts at launch, and with -RemoteViewersOnLoopback too, on
        // 127.0.0.1 alone. Compiles in release too, where it serves nothing.
        ExampleRemoteServer.offer(ConsoleModel.shared, id: ConsolePlugin().id)
        ExampleRemoteServer.offer(NetworkModel.shared, id: NetworkPlugin().id)
        ExampleRemoteServer.install()

        setupMenuBar()
        // Launched with -AppKitWindow, the app opens only its AppKit window: no SwiftUI root at all.
        if ProcessInfo.processInfo.arguments.contains(ExampleAppKitWindowController.launchArgument) {
            showAppKitWindow()
            ExampleAppKitWindowController.openDrawerIfAsked()
        } else {
            createMainWindow()
            windows.openNewWindowIfAsked(behind: mainWindow)
        }
        remoteWindow.openIfAsked()
        ExamplePresentations.runAppModalAlertIfAsked()
        // Launched with -RunTestBench and action identifiers (or all), runs those test bench actions,
        // then opens the drawer at the plugin -OpenDebugDrawerPlugin names.
        TestBench.runFromLaunchArguments()
    }

    /// The plugins installed with one call each, which compile in release too and do nothing there;
    /// a function of its own to keep launch short enough to read.
    private func installShippedPlugins() {
        ExampleConsole.install()
        // Links DebugDrawerDiskIOInterposer (Example/BUILD.bazel): Swift's Data and FileHandle calls too.
        DebugDrawer.shared.unsafeInstallDiskIOWithInterposing()
        DebugDrawer.shared.installViewInspector()
        ExampleViewInspector.applyLaunchArguments()
        DebugDrawer.shared.installAccessibility()
        DebugDrawer.shared.installPerformance()
        DebugDrawer.shared.installEnergy()
        DebugDrawer.shared.installScreenshot()
        // Sample values: a real app's CI passes its own, here or through the Info.plist keys
        // (this Info.plist sets DebugDrawerCIBuildNumber).
        DebugDrawer.shared.installAppInfo(buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "main"))
        DebugDrawer.shared.installKeychain()
        DebugDrawer.shared.installLocation()
        DebugDrawer.shared.installLoadedLibraries()
        DebugDrawer.shared.installCookies()
        DebugDrawer.shared.installLaunchTime()
        ExampleTweaks.install()
        ExampleFeatureFlags.install()
        DebugDrawer.shared.reportUploader = FolderReportUploader()
    }

    func application(_: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }

    func application(_: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushNotifications.didFailToRegisterForRemoteNotifications(withError: error)
    }

    private func createMainWindow() {
        mainWindow = ExampleWindows.makeWindow(title: "DebugDrawer Example", autosaveName: "DebugDrawerExample")
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Release builds have no drawer, so there it does nothing. A menu item, unlike a hidden button, is listed
        // in the menu bar and reachable through accessibility.
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
        debugMenu.addItem(withTitle: "Show AppKit Window", action: #selector(showAppKitWindow), keyEquivalent: "").target = self
        debugMenu.addItem(withTitle: "New Window", action: #selector(ExampleWindows.newWindow), keyEquivalent: "n").target = windows
        debugMenu.addItem(withTitle: "Remote Viewer", action: #selector(ExampleRemoteWindow.show), keyEquivalent: "").target = remoteWindow
        debugMenuItem.submenu = debugMenu
        mainMenu.addItem(debugMenuItem)

        NSApp.mainMenu = mainMenu
    }

    /// Shows the window whose content is AppKit's alone, made the first time it is asked for.
    @objc private func showAppKitWindow() {
        if appKitWindow == nil { appKitWindow = ExampleAppKitWindowController() }
        appKitWindow?.showWindow(nil)
    }

    @objc private func toggleDebugDrawer() {
        DebugDrawer.shared.toggle()
    }

    // AppKit enables a menu item during an app-modal session only when its target works when modal,
    // so Ctrl+D opens the drawer above an app-modal alert too.
    @objc var worksWhenModal: Bool {
        true
    }

    // Shows what a plugin's notice looks like: a badge on Network and a toast that opens it.
    @objc private func postSampleNotice() {
        let network = NetworkPlugin()
        network.setBadge(1)
        network.postToast("GET /api/orders failed with 500")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

// MARK: - Example content

struct ExampleContentView: View {
    /// The window's title, which its local plugin shows in that window's drawer alone.
    var windowName = "DebugDrawer Example"
    // Launched with -ShowTestBench, the window opens on the test bench.
    @State private var selectedItem: String? = ProcessInfo.processInfo.arguments.contains("-ShowTestBench") ? Self.testBench : nil
    private static let testBench = "Test Bench"

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
                // An action for each plugin that records something, grouped by plugin.
                Section("Debug") {
                    Label(Self.testBench, systemImage: "hammer")
                        .tag(Self.testBench)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            if selectedItem == Self.testBench {
                TestBenchList()
            } else {
                ExampleMainScreen()
            }
        }
        // Listed in the View Inspector's SwiftUI Renders: the window renders again when the
        // selection changes (ExampleMainScreen when the counter does), and not while the app sits idle.
        .trackRenders("ExampleContentView")
        // Redraws the app's own strings when a Localization mode changes; beneath .debugDrawer(),
        // so the drawer keeps its place.
        .debugLocalization()
        .debugAccessibilityOverrides()
        // The design comp over the app, beneath .debugDrawer(), so the drawer stays above it.
        .debugDesignOverlay()
        .debugGrid()
        // Listed in this window's drawer only.
        .debugLocalPlugin(ExampleWindowPlugin(windowName: windowName))
        .debugDrawer()
        // Launched with -OpenDebugDrawer, the key window opens with the drawer open, so it can be
        // checked without a hand, like the iOS example. Only the main window's view asks, so with
        // -NewWindow the drawer opens once, in whichever window is key.
        .onAppear {
            guard windowName == "DebugDrawer Example" else { return }
            if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
                DebugDrawer.shared.toggle()
            }
        }
    }
}
