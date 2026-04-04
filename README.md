# DebugDrawer

A plugin-based debug drawer for macOS apps. Slide-in panel with modular debugging tools — pick only what you need.

Built for SwiftUI + AppKit. Everything compiles to no-ops in release builds.

## Quick Start

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/user/DebugDrawer", from: "1.0.0"),
]

// Pick only the plugins you want:
.target(name: "MyApp", dependencies: [
    .product(name: "DebugDrawer", package: "DebugDrawer"),
    .product(name: "DebugDrawerConsolePlugin", package: "DebugDrawer"),
    .product(name: "DebugDrawerPerformancePlugin", package: "DebugDrawer"),
])
```

```swift
import DebugDrawer
import DebugDrawerConsolePlugin
import DebugDrawerPerformancePlugin

// Register plugins at app startup
#if DEBUG
DebugDrawer.shared.installConsole()
DebugDrawer.shared.installPerformance()
#endif

// Attach to your root view
ContentView()
    .debugDrawer()  // Ctrl+D to toggle
```

## Plugins

Each plugin is a separate library with no transitive dependency conflicts.

### Console
`DebugDrawerConsolePlugin` — captures stdout, stderr, and os_log entries in a scrollable NSTextView. Level filtering, auto-follow, multi-line text selection.

### View Inspector
`DebugDrawerViewInspectorPlugin` — view borders with depth coloring, alignment grid with adjustable spacing/color/opacity, click indicators, animation speed control, SwiftUI render tracking (via NSView.layout swizzle), 3D view hierarchy (SceneKit), measurement tool, attribute inspector.

### Accessibility
`DebugDrawerAccessibilityPlugin` — runtime environment overrides (color scheme, dynamic type, layout direction, locale) plus a built-in accessibility auditor that checks for missing labels, small hit targets, low contrast, and heading hierarchy issues. Scores your app 0-100 with WCAG references.

### Performance
`DebugDrawerPerformancePlugin` — live FPS (via CVDisplayLink) and memory usage with sparkline graphs. Min/avg FPS and peak memory stats.

### Energy
`DebugDrawerEnergyPlugin` — battery level and charging state (IOKit), CPU usage per-process (Mach thread info), thermal state, energy impact rating with sparklines.

### Network
`DebugDrawerNetworkPlugin` — URLProtocol-based HTTP interception. Logs every URLSession request with method, URL, status, timing, headers, and body. JSON auto-pretty-prints. Filter by status code.

### Disk I/O
`DebugDrawerDiskIOPlugin` — FileManager method swizzling to track reads, writes, deletes, directory listings, and stat calls. Flags main-thread I/O. Duration tracking for slow operations.

### App Info
`DebugDrawerAppInfoPlugin` — bundle ID, version, build, macOS version, memory usage, uptime, PID, architecture, CPU count, sandbox status. Copy button for bug reports.

### UserDefaults
`DebugDrawerUserDefaultsPlugin` — browse, search, edit (string/bool/number), and delete UserDefaults keys. Filters out system keys by default.

### Keychain
`DebugDrawerKeychainPlugin` — browse generic and internet passwords. Copy values, delete entries.

### Screenshot
`DebugDrawerScreenshotPlugin` — capture the app window to desktop or clipboard. Optional "hide drawer" toggle. Uses ScreenCaptureKit.

### File Browser
`DebugDrawerFileBrowserPlugin` — browse App Support and Caches directories. Tree view with disclosure groups, file sizes, copy path, reveal in Finder.

## Plugin Types

### Global Plugins
Registered once at startup, always visible in the drawer.

```swift
DebugDrawer.shared.installConsole()
```

### Local Plugins
Attached to a view — appear when the view is on screen, disappear when it leaves.

```swift
struct MyPlugin: DebugDrawerPlugin {
    var title = "Cache Tools"
    var icon = "paintbrush"
    var body: some View {
        Button("Clear Cache") { MyCache.shared.clear() }
    }
}

MyView()
    .debugLocalPlugin(MyPlugin())
```

Local plugins appear above global plugins in the drawer. The `contentIdentifier` property controls re-registration when the plugin's data changes:

```swift
struct FilePlugin: DebugDrawerPlugin {
    var title = "Current File"
    var icon = "doc"
    let filePath: String
    var contentIdentifier: String { filePath }
    var body: some View { Text(filePath) }
}
```

## Writing Custom Plugins

```swift
import DebugDrawer

struct MyPlugin: DebugDrawerPlugin {
    var title = "My Tool"
    var icon = "wrench"  // SF Symbol name

    var body: some View {
        VStack {
            Text("Hello from debug drawer")
            Button("Do Thing") { /* ... */ }
        }
    }
}

// Register globally
DebugDrawer.shared.registerGlobal(MyPlugin())

// Or attach locally to a view
.debugLocalPlugin(MyPlugin())
```

The protocol exists in all build configurations (so conformances compile in release), but `.debugDrawer()` and `.debugLocalPlugin()` are no-ops outside `#if DEBUG`.

## Environment Overrides

The accessibility plugin provides runtime environment overrides:

```swift
import DebugDrawerAccessibilityPlugin

ContentView()
    .debugAccessibilityOverrides()  // must be above .debugDrawer()
    .debugDrawer()
```

## Grid Overlay

```swift
import DebugDrawerViewInspectorPlugin

ContentView()
    .debugGrid()  // controlled from View Inspector plugin
    .debugDrawer()
```

## Development

```bash
just build       # Bazel build all libraries
just test        # Run all 13 test suites
just run         # Build and launch example app
just build-spm   # Verify SPM Package.swift works
just clean       # Clean Bazel artifacts
```

Requires Bazel 9.0.1, macOS 15.0+, Swift 6.

## License

MIT
