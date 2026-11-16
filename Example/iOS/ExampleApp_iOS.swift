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
import DebugDrawerHangDetectorPlugin
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
    init() {
        // First, so a crash in the rest of startup is recorded. It compiles in release, where it
        // installs nothing; launched with -CrashOnLaunch, the app crashes right after it.
        CrashReports.install()
        if ProcessInfo.processInfo.arguments.contains(ExampleCrash.launchArgument) {
            ExampleCrash.crash()
        }
        // Compiles in release too, where it starts nothing; launched with -HangOnLaunch, the app
        // blocks its main thread for 500 ms once it first goes idle.
        HangDetector.install()
        if ProcessInfo.processInfo.arguments.contains(ExampleHang.launchArgument) {
            ExampleHang.blockAfterLaunch()
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
    }

    var body: some Scene {
        WindowGroup {
            ExampleContentView_iOS()
                .debugAccessibilityOverrides()
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
                Section("Controls") {
                    HStack {
                        Button("Increment") { counter += ExampleTweaks.counterStep.value }
                        Button("Print") { print("Counter: \(counter)") }
                        Button("Reset") { counter = 0 }
                    }
                    .buttonStyle(.bordered)

                    Button("Show Sheet") { isShowingSheet = true }
                    // Crash Reports shows the crash on the next launch.
                    Button("Crash the App", role: .destructive) { ExampleCrash.crash() }
                    // Hangs reports the stall with its stack and a toast.
                    Button("Block the Main Thread for 500 ms") { ExampleHang.blockMainThread() }

                    Text("Counter: \(counter)")
                        .font(.title2.monospacedDigit())
                        .accessibilityAddTraits(.isHeader)

                    ExampleTweaksBanner()
                    ExampleFeatureFlagsSummary()
                }

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
