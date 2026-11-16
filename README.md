# DebugDrawer

A plugin-based debug drawer for macOS and iOS apps: a slide-in panel of debugging tools, each its
own library, so an app links only the tools it wants. Built for SwiftUI. Every entry point compiles
to a no-op outside `DEBUG`, so builds that ship to end users carry none of it.

## Installation

DebugDrawer requires Swift 6.3 and supports macOS 15 and iOS 17 or later.

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/DebugDrawer", from: "0.0.4"),
],
```

Then add the core and only the plugins you want to your target. Each plugin is a separate library:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "DebugDrawer", package: "DebugDrawer"),
    .product(name: "DebugDrawerConsolePlugin", package: "DebugDrawer"),
    .product(name: "DebugDrawerPerformancePlugin", package: "DebugDrawer"),
    // ... as many or as few as you need (Modules, below)
]),
```

## Usage

Every example here is a test in `Tests/DebugDrawerTests`, so it cannot drift from the code.

A plugin is a title, an SF Symbol and a SwiftUI body. Register it globally, or attach it to the
view it belongs to, attach the drawer once to the root view, and open it from your own trigger:

```swift
import DebugDrawer
import SwiftUI

struct CachePlugin: DebugDrawerPlugin {
    var title = "Cache"
    var icon = "trash" // an SF Symbol

    var body: some View {
        Button("Clear URL cache") { URLCache.shared.removeAllCachedResponses() }
    }
}

// Global: registered once at startup, always in the drawer.
DebugDrawer.shared.registerGlobal(CachePlugin())

// The drawer, attached once to the root view.
let root = Text("Home").debugDrawer()

// Local: in the drawer while its view is on screen.
let settings = Text("Settings").debugLocalPlugin(CachePlugin())

// Open or close it from whatever trigger suits the app.
DebugDrawer.shared.toggle()
```

`DebugDrawer.shared` and the plugins' `install*()` calls exist in debug builds only, so wrap them
in `#if DEBUG`. The `DebugDrawerPlugin` protocol exists in every configuration, so conformances
compile in release, and `.debugDrawer()` and `.debugLocalPlugin()` do nothing there.

### Searching plugins and actions

The open drawer has a search field that finds plugins by title and runs the actions they declare.
Cmd-K focuses it while the drawer is open; it never opens the drawer. The arrow keys move through
the results and Return picks one: a plugin is scrolled to and expanded, an action runs. A plugin
declares actions, each found by its title or its keywords; it declares none unless it says so:

```swift
struct SessionPlugin: DebugDrawerPlugin {
    var title = "Session"
    var icon = "person.crop.circle"

    var body: some View {
        Text("Signed in")
    }

    var actions: [DebugDrawerAction] {
        [
            DebugDrawerAction("Expire token", keywords: ["auth", "logout"]) {
                UserDefaults.standard.removeObject(forKey: "authToken")
            },
        ]
    }
}
```

### Installing the shipped plugins

Each plugin installs itself with one call at startup. All of them:

```swift
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

Each call needs its plugin's module imported (`import DebugDrawerConsolePlugin`, and so on).

### Opening the drawer

The drawer doesn't decide how it opens. Call `DebugDrawer.shared.toggle()` from whatever trigger
makes sense for your app:

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
```

### Optional modifiers

```swift
import DebugDrawerAccessibilityPlugin
import DebugDrawerViewInspectorPlugin

ContentView()
    .debugAccessibilityOverrides()  // environment overrides; must be above .debugDrawer()
    .debugGrid()                    // alignment grid, controlled from the View Inspector plugin
    .debugDrawer()
```

## Modules

| Module | Holds |
|---|---|
| `DebugDrawer` | The drawer: its window, the plugin protocol and registry, and release-build stand-ins |
| `DebugDrawerConsolePlugin` | `os_log` entries (stdout and stderr on macOS): level filter, search, auto-follow, copy |
| `DebugDrawerViewInspectorPlugin` | View borders by depth, alignment grid, click indicators, animation speed, SwiftUI render tracking, hierarchy snapshot |
| `DebugDrawerAccessibilityPlugin` | Runtime overrides of color scheme, Dynamic Type, layout direction, locale and the system accessibility settings SwiftUI exposes, each beside the system's value |
| `DebugDrawerPerformancePlugin` | Live FPS and memory with sparkline graphs |
| `DebugDrawerEnergyPlugin` | Battery level and charging, CPU load and thermal state |
| `DebugDrawerNetworkPlugin` | URLProtocol HTTP interception: method, URL, status, timing, headers, body, cURL export |
| `DebugDrawerDiskIOPlugin` | FileManager reads, writes, deletes and listings, flagging main-thread I/O |
| `DebugDrawerAppInfoPlugin` | Bundle, version, OS, memory, uptime, process, debugger, screen and reachability facts |
| `DebugDrawerUserDefaultsPlugin` | Browse, search, edit and delete UserDefaults keys |
| `DebugDrawerKeychainPlugin` | Generic and internet passwords: copy and delete entries |
| `DebugDrawerScreenshotPlugin` | The app window captured to a file or the clipboard, optionally without the drawer |
| `DebugDrawerFileBrowserPlugin` | The app's Application Support and Caches directories: delete and share files |
| `DebugDrawerLocationPlugin` | Spoofed CLLocationManager coordinates: presets and a custom latitude and longitude |
| `DebugDrawerLoadedLibrariesPlugin` | Every loaded image, grouped as app, third-party and system, with UUIDs and load addresses |
| `DebugDrawerDeepLinkPlugin` | Opens deep links and keeps a history of them |
| `DebugDrawerCookiesPlugin` | Browse, search and delete HTTPCookieStorage cookies |
| `DebugDrawerLaunchTimePlugin` | Pre-main, app-init-to-first-frame and total launch time |

## Development

Bazel is the development build; SwiftPM is the published package. Both are generated from
`scripts/modules.py`.

| Command | Does |
|---|---|
| `just test` | Build and run every test |
| `just verify` | The tests under Bazel and under SwiftPM |
| `just modules` | Regenerate `Package.swift` and every `BUILD.bazel` |
| `just docs` | The DocC site into `.build/docs` |
| `just generate` | An Xcode project from the Bazel graph |
| `just run [macOS\|iOS]` | Build and launch the example app |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

MIT. See `LICENSE`.
