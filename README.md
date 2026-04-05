# DebugDrawer

A plugin-based debug drawer for macOS and iOS apps. Slide-in panel with modular debugging tools — pick only what you need.

Built for SwiftUI. Everything compiles to no-ops in release builds.

## Installation

Add DebugDrawer to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/DebugDrawer", from: "0.0.1"),
]
```

Then add only the plugins you want to your target:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "DebugDrawer", package: "DebugDrawer"),
    .product(name: "DebugDrawerConsolePlugin", package: "DebugDrawer"),
    .product(name: "DebugDrawerPerformancePlugin", package: "DebugDrawer"),
    // ... add as many or as few as you need
])
```

Each plugin is a separate library. No transitive dependency conflicts — you only pull in what you use.

## Setup

### 1. Register plugins at app startup

Here's every plugin — copy what you want:

```swift
import DebugDrawer
import DebugDrawerConsolePlugin
import DebugDrawerViewInspectorPlugin
import DebugDrawerAccessibilityPlugin
import DebugDrawerPerformancePlugin
import DebugDrawerEnergyPlugin
import DebugDrawerNetworkPlugin
import DebugDrawerDiskIOPlugin
import DebugDrawerScreenshotPlugin
import DebugDrawerAppInfoPlugin
import DebugDrawerUserDefaultsPlugin
import DebugDrawerKeychainPlugin
import DebugDrawerFileBrowserPlugin
import DebugDrawerLocationPlugin
import DebugDrawerLoadedLibrariesPlugin
import DebugDrawerDeepLinkPlugin
import DebugDrawerCookiesPlugin
import DebugDrawerLaunchTimePlugin

// In your app's init or applicationDidFinishLaunching:
#if DEBUG
DebugDrawer.shared.installConsole()
DebugDrawer.shared.installViewInspector()
DebugDrawer.shared.installAccessibility()
DebugDrawer.shared.installPerformance()
DebugDrawer.shared.installEnergy()
DebugDrawer.shared.installNetwork()
DebugDrawer.shared.installDiskIO()
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
#endif
```

And the matching SPM dependencies (copy all or pick what you need):

```swift
.product(name: "DebugDrawer", package: "DebugDrawer"),
.product(name: "DebugDrawerConsolePlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerViewInspectorPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerAccessibilityPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerPerformancePlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerEnergyPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerNetworkPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerDiskIOPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerScreenshotPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerAppInfoPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerUserDefaultsPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerKeychainPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerFileBrowserPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerLocationPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerLoadedLibrariesPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerDeepLinkPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerCookiesPlugin", package: "DebugDrawer"),
.product(name: "DebugDrawerLaunchTimePlugin", package: "DebugDrawer"),
```

Or just grab a few — each one is independent.
```

### 2. Attach the drawer to your root view

```swift
ContentView()
    .debugDrawer()
```

### 3. Wire up your own trigger

The drawer doesn't assume how you want to open it. Call `DebugDrawer.shared.toggle()` from whatever trigger makes sense for your app:

```swift
// Keyboard shortcut (Ctrl+D)
.background {
    Button("") { DebugDrawer.shared.toggle() }
        .keyboardShortcut("d", modifiers: .control)
        .hidden()
}

// Shake gesture (iOS)
override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    if motion == .motionShake { DebugDrawer.shared.toggle() }
}

// Triple-tap (iOS)
.onTapGesture(count: 3) { DebugDrawer.shared.toggle() }

// Menu item, button, whatever you want
Button("Debug") { DebugDrawer.shared.toggle() }
```

## Available Plugins

### Console
`DebugDrawerConsolePlugin` — captures os_log entries (stdout/stderr on macOS). Level filtering, search, auto-follow, multi-line text selection, copy all.

### View Inspector
`DebugDrawerViewInspectorPlugin` — view borders with depth coloring, alignment grid (color/opacity/spacing), click indicators, animation speed control, SwiftUI render tracking, view hierarchy snapshot.

### Accessibility
`DebugDrawerAccessibilityPlugin` — runtime environment overrides: color scheme, dynamic type, layout direction, locale.

### Performance
`DebugDrawerPerformancePlugin` — live FPS and memory usage with sparkline graphs.

### Energy
`DebugDrawerEnergyPlugin` — battery level/charging (IOKit on macOS, UIDevice on iOS), CPU usage, thermal state, energy impact rating.

### Network
`DebugDrawerNetworkPlugin` — URLProtocol-based HTTP interception. Logs requests with method, URL, status, timing, headers, body. JSON pretty-printing, cURL export, stats summary.

### Disk I/O
`DebugDrawerDiskIOPlugin` — FileManager swizzling to track reads, writes, deletes, directory listings. Flags main-thread I/O.

### App Info
`DebugDrawerAppInfoPlugin` — bundle ID, version, build, OS version, memory, uptime, PID, architecture, screen resolution, network reachability, launch time.

### UserDefaults
`DebugDrawerUserDefaultsPlugin` — browse, search, edit (string/bool/number), and delete UserDefaults keys.

### Keychain
`DebugDrawerKeychainPlugin` — browse generic and internet passwords. Copy values, delete entries.

### Screenshot
`DebugDrawerScreenshotPlugin` — capture the app window to desktop or clipboard. Optional "hide drawer" toggle.

### File Browser
`DebugDrawerFileBrowserPlugin` — browse App Support and Caches directories. Delete and share files.

### Location Simulator
`DebugDrawerLocationPlugin` — spoof CLLocationManager coordinates. Preset locations, custom lat/lon input.

### Loaded Libraries
`DebugDrawerLoadedLibrariesPlugin` — list all dynamically loaded dylibs grouped by App/Third-Party/System.

### Deep Link Tester
`DebugDrawerDeepLinkPlugin` — test URL schemes with history and preset templates.

### HTTP Cookies
`DebugDrawerCookiesPlugin` — browse, search, and delete HTTP cookies.

### Launch Time
`DebugDrawerLaunchTimePlugin` — measure app startup time with pre-main/main-to-first-frame breakdown.

## Plugin Types

### Global Plugins
Registered once at startup, always visible:

```swift
DebugDrawer.shared.installConsole()
```

### Local Plugins
Tied to a view's lifecycle — appear when the view is on screen:

```swift
struct CachePlugin: DebugDrawerPlugin {
    var title = "Cache"
    var icon = "paintbrush"
    var body: some View {
        Button("Clear") { MyCache.shared.clear() }
    }
}

MyView()
    .debugLocalPlugin(CachePlugin())
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

The `DebugDrawerPlugin` protocol exists in all build configurations so conformances compile in release. `.debugDrawer()` and `.debugLocalPlugin()` are no-ops outside `#if DEBUG`.

## Optional Modifiers

### Environment Overrides
```swift
import DebugDrawerAccessibilityPlugin

ContentView()
    .debugAccessibilityOverrides()  // must be above .debugDrawer()
    .debugDrawer()
```

### Grid Overlay
```swift
import DebugDrawerViewInspectorPlugin

ContentView()
    .debugGrid()  // controlled from View Inspector plugin
    .debugDrawer()
```

## Development

Uses [just](https://github.com/casey/just) as a task runner. Run `just --list` to see available commands.

Requires Bazel 9.0.1, macOS 15.0+ / iOS 17.0+, Swift 6.

## License

MIT
