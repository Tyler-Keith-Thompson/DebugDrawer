import DebugDrawer
import SwiftUI

// No shipped plugin builds for tvOS yet (EXTRA_PLATFORMS in scripts/modules.py), so the example
// registers plugins of its own, written against core alone as a host app's would be.
@main
struct DebugDrawerExampleTVOSApp: App {
    init() {
        #if DEBUG
            DebugDrawer.shared.registerGlobal(ExampleBuildPlugin())
            DebugDrawer.shared.registerGlobal(ExampleCachePlugin())
            DebugDrawer.shared.registerGlobal(ExamplePlaybackPlugin())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ExampleContentView_tvOS()
                .debugDrawer()
                // The library binds no remote button (it adds no global trigger), so the app opens
                // the drawer: from a button in the list, and from Play/Pause here. Attached outside
                // .debugDrawer(), it also closes the drawer while focus is in it.
                #if DEBUG
                    .onPlayPauseCommand { DebugDrawer.shared.toggle() }
                #endif
                // Launched with -OpenDebugDrawer, the app starts with the drawer open, so it can be
                // checked without a remote:
                // `xcrun simctl launch booted com.debugdrawer.example.tvos -OpenDebugDrawer`.
                .onAppear {
                    #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-OpenDebugDrawer"), !DebugDrawer.shared.isOpen {
                            DebugDrawer.shared.toggle()
                        }
                    #endif
                }
        }
    }
}

struct ExampleContentView_tvOS: View {
    @State private var counter = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Controls") {
                    Button("Increment") { counter += 1 }
                    Button("Reset") { counter = 0 }
                    Text("Counter: \(counter)")
                        .font(.title2.monospacedDigit())
                        .accessibilityAddTraits(.isHeader)
                }

                // The drawer exists in debug builds only.
                #if DEBUG
                    Section("Debug") {
                        Button {
                            DebugDrawer.shared.toggle()
                        } label: {
                            Label("Debug Drawer", systemImage: "ladybug")
                        }
                    }
                #endif

                Section("Items") {
                    ForEach(1 ... 20, id: \.self) { item in
                        Label("Item \(item)", systemImage: "circle.fill")
                    }
                }
            }
            .navigationTitle("DebugDrawer Example")
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
/// tvOS, which has no pasteboard; the plugin keeps it so the same body builds everywhere.
struct ExampleCachePlugin: DebugDrawerPlugin {
    var title = "Cache"
    var icon = "externaldrive"

    var body: some View {
        let usage = "\(URLCache.shared.currentDiskUsage / 1024) KB"
        DebugDrawerKeyValueRow("Disk usage", value: usage)
        DebugDrawerCopyButton("Copy Usage") { usage }
        Button("Clear URL cache") { URLCache.shared.removeAllCachedResponses() }
    }
}

/// A focusable control inside a section, to check focus moves into a plugin's body.
struct ExamplePlaybackPlugin: DebugDrawerPlugin {
    var title = "Playback"
    var icon = "play.rectangle"

    var body: some View {
        DebugDrawerKeyValueRow("Engine", value: "AVPlayer")
        Button("Log a stall") {}
    }
}
