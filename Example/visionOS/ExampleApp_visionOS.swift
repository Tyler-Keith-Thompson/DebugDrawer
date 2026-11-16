import DebugDrawer
import SwiftUI

// No shipped plugin builds for visionOS yet (EXTRA_PLATFORMS in scripts/modules.py), so the
// example registers plugins of its own, written against core alone as a host app's would be.
@main
struct DebugDrawerExampleVisionOSApp: App {
    init() {
        #if DEBUG
            DebugDrawer.shared.registerGlobal(ExampleBuildPlugin())
            DebugDrawer.shared.registerGlobal(ExampleCachePlugin())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ExampleContentView_visionOS()
                .debugDrawer()
                // Launched with -OpenDebugDrawer, the window opens with the drawer open, so it can
                // be checked without a hand:
                // `xcrun simctl launch booted com.debugdrawer.example.visionos -OpenDebugDrawer`.
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

struct ExampleContentView_visionOS: View {
    @State private var counter = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Controls") {
                    HStack {
                        Button("Increment") { counter += 1 }
                        Button("Reset") { counter = 0 }
                    }
                    Text("Counter: \(counter)")
                        .font(.title2.monospacedDigit())
                        .accessibilityAddTraits(.isHeader)
                }

                Section("Items") {
                    ForEach(1 ... 20, id: \.self) { item in
                        Label("Item \(item)", systemImage: "circle.fill")
                    }
                }
            }
            .navigationTitle("DebugDrawer Example")
            .toolbar {
                // The drawer exists in debug builds only.
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

/// The shared URL cache's disk usage, with a copy button and a way to clear it.
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
