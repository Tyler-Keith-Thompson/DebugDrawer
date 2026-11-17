import DebugDrawer
import SwiftUI

// No shipped plugin builds for watchOS yet (EXTRA_PLATFORMS in scripts/modules.py), so the
// example registers plugins of its own, written against core alone as a host app's would be.
@main
struct DebugDrawerExampleWatchOSApp: App {
    init() {
        DebugDrawer.shared.registerGlobal(ExampleBuildPlugin())
        DebugDrawer.shared.registerGlobal(ExampleCachePlugin())
        DebugDrawer.shared.registerGlobal(ExampleWorkoutPlugin())
    }

    var body: some Scene {
        WindowGroup {
            ExampleContentView_watchOS()
                .debugDrawer()
                // Launched with -OpenDebugDrawer, the app starts with the drawer open, so it can be
                // checked without tapping:
                // `xcrun simctl launch booted com.debugdrawer.example.watchos -OpenDebugDrawer`.
                // -OpenDebugDrawerPlugin <id> opens it at one plugin, through a toast, as a plugin
                // that raises one would.
                .onAppear {
                    openFromLaunchArguments(ProcessInfo.processInfo.arguments)
                }
        }
    }

    @MainActor
    private func openFromLaunchArguments(_ arguments: [String]) {
        let drawer = DebugDrawer.shared
        if let flag = arguments.firstIndex(of: "-OpenDebugDrawerPlugin"), arguments.indices.contains(flag + 1) {
            drawer.postToast("Opened at launch", fromPlugin: arguments[flag + 1])
            drawer.openToast()
        } else if arguments.contains("-OpenDebugDrawer"), !drawer.isOpen {
            drawer.toggle()
        }
    }
}

struct ExampleContentView_watchOS: View {
    @State private var counter = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Controls") {
                    Button("Increment") { counter += 1 }
                    Button("Reset") { counter = 0 }
                    Text("Counter: \(counter)")
                        .font(.headline.monospacedDigit())
                        .accessibilityAddTraits(.isHeader)
                }

                // The library binds no gesture or button (it adds no global trigger), so the app
                // opens the drawer: here from a button. Release builds have no drawer, so there it does nothing.
                Section("Debug") {
                    Button {
                        DebugDrawer.shared.toggle()
                    } label: {
                        Label("Debug Drawer", systemImage: "ladybug")
                    }
                }
            }
            .navigationTitle("Example")
        }
    }
}

/// The app's bundle facts, from core's key-value rows.
struct ExampleBuildPlugin: DebugDrawerPlugin {
    var title = "Build"
    var icon = "hammer"

    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        DebugDrawerKeyValueRow("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
        DebugDrawerKeyValueRow("Version", value: info["CFBundleShortVersionString"] as? String ?? "—")
        DebugDrawerKeyValueRow("OS", value: ProcessInfo.processInfo.operatingSystemVersionString)
    }
}

/// The shared URL cache's disk usage and a way to clear it. Its copy button draws nothing on
/// watchOS, which has no pasteboard; the plugin keeps it so the same body builds everywhere.
struct ExampleCachePlugin: DebugDrawerPlugin {
    var title = "Cache"
    var icon = "externaldrive"
    var category = "Storage"

    var body: some View {
        let usage = "\(URLCache.shared.currentDiskUsage / 1024) KB"
        DebugDrawerKeyValueRow("Disk usage", value: usage)
        DebugDrawerCopyButton("Copy Usage") { usage }
        Button("Clear URL cache") { URLCache.shared.removeAllCachedResponses() }
    }
}

/// A plugin with a control, in a category of its own, so the list shows more than one section.
struct ExampleWorkoutPlugin: DebugDrawerPlugin {
    var title = "Workout"
    var icon = "figure.run"
    var category = "Health"

    var body: some View {
        DebugDrawerKeyValueRow("Session", value: "Idle")
        Button("Log a heart rate sample") {}
    }
}
