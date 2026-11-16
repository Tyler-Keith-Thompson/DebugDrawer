import AppKit
import DebugDrawer
import DebugDrawerAccessibilityPlugin
import DebugDrawerAppInfoPlugin
import DebugDrawerConsolePlugin
import DebugDrawerDiskIOPlugin
import DebugDrawerEnergyPlugin
import DebugDrawerFileBrowserPlugin
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
        if ProcessInfo.processInfo.arguments.contains(ExampleCrash.launchArgument) {
            ExampleCrash.crash()
        }
        #if DEBUG
            DebugDrawer.shared.installConsole()
            DebugDrawer.shared.installNetwork()
            DebugDrawer.shared.installDiskIO()
            DebugDrawer.shared.installViewInspector()
            DebugDrawer.shared.installAccessibility()
            DebugDrawer.shared.installPerformance()
            DebugDrawer.shared.installEnergy()
            DebugDrawer.shared.installScreenshot()
            DebugDrawer.shared.installAppInfo()
            DebugDrawer.shared.installUserDefaults()
            DebugDrawer.shared.installKeychain()
            DebugDrawer.shared.installFileBrowser()
            DebugDrawer.shared.installLocation()
            DebugDrawer.shared.installLoadedLibraries()
            DebugDrawer.shared.installDeepLink()
            DebugDrawer.shared.installCookies()
            DebugDrawer.shared.installLaunchTime()
            ExampleTweaks.install()
            ExampleFeatureFlags.install()
            DebugDrawer.shared.reportUploader = FolderReportUploader()
        #endif

        setupMenuBar()
        createMainWindow()
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
                Text("DebugDrawer Example")
                    .font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)

                Text("Press Ctrl+D to open the debug drawer")
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 16) {
                    Button("Increment") { counter += ExampleTweaks.counterStep.value }
                    Button("Print") { print("Counter: \(counter)") }
                    Button("Reset") { counter = 0 }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Counter actions")

                Text("Counter: \(counter)")
                    .font(.title2.monospacedDigit())
                    .accessibilityAddTraits(.isHeader)

                ExampleTweaksBanner()
                ExampleFeatureFlagsSummary()

                // Crash Reports shows the crash on the next launch.
                Button("Crash the App", role: .destructive) { ExampleCrash.crash() }

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
        .debugAccessibilityOverrides()
        .debugGrid()
        .debugDrawer()
    }
}
