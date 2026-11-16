# DebugDrawer

A plugin-based debug drawer for macOS and iOS apps: a slide-in panel of debugging tools, each its
own library, so an app links only the tools it wants. Built for SwiftUI. Every entry point compiles
to a no-op outside `DEBUG`, so builds that ship to end users carry none of it.

## Installation

DebugDrawer requires Swift 6.3 and supports macOS 15 and iOS 17 or later. The core module,
`DebugDrawer` (the drawer, the plugin protocol and the shared views), also builds for visionOS 1
or later, where the drawer opens in an ornament beside the window rather than over it, and for
tvOS 17 or later, where the remote's focus moves through it (Apple TV, below). The shipped plugins
build for macOS and iOS only so far, so a visionOS or tvOS app registers plugins of its own.

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
        let usage = "\(URLCache.shared.currentDiskUsage / 1024) KB"
        DebugDrawerKeyValueRow("Disk usage", value: usage)
        DebugDrawerCopyButton("Copy Usage") { usage }
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

### Building a plugin's view

Core has the views the shipped plugins are built from, so a plugin of your own looks like them:

| View | Shows |
|---|---|
| `DebugDrawerKeyValueRow` | A label and a monospaced value; pass `redacted:` to mask a sensitive value until revealed |
| `DebugDrawerCopyButton` | A button that copies the text its closure returns when pressed |
| `DebugDrawerStatBadge` | A figure over its caption, for a row of totals |
| `DebugDrawerSparkline` | A line graph of recent samples |
| `DebugDrawerSearchableList` | A filter field above a scrolling list of rows; the plugin filters the rows |

Each lays itself out for accessibility text sizes and labels itself for VoiceOver. They exist in
every configuration, so a plugin's body compiles in release, where they draw nothing.

### Grouping, pinning and ordering

The drawer lists global plugins by `category`, a string a plugin may declare; one that declares
none is in `General`, listed last. Right-click a plugin's header (long-press on iOS) to pin it to
the top or move it up or down its group. The drawer remembers pins, order and the plugin last used,
and opens at that plugin after a relaunch.

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

### Badges and toasts

A plugin can raise a problem while the drawer is closed. A badge puts a count on the plugin's
section header until the plugin clears it. A toast appears in the window's corner while the drawer
is closed; tapping it opens the drawer with that plugin expanded and scrolled into view, and its
close button dismisses it. Posts from one plugin coalesce into one toast that shows the latest
message and how many posts it stands for; a post while the drawer is open is dropped. In release
builds these calls compile and do nothing.

```swift
struct UploadsPlugin: DebugDrawerPlugin {
    var title = "Uploads"
    var icon = "arrow.up.circle"

    var body: some View {
        Text("No uploads")
    }
}

let uploads = UploadsPlugin()
uploads.setBadge(2)
uploads.postToast("Upload of report.pdf failed")
uploads.clearBadge()
```

### Floating HUD

A plugin can offer a compact readout for the floating HUD, which stays on screen while the drawer
is closed. Choose Show in HUD from a plugin's context menu in the drawer to pin its readout; drag
the HUD anywhere in the window. Only the HUD itself takes touches; the rest of the window reaches
the app. The pinned readouts and the HUD's position are remembered across launches, and the
Screenshot plugin leaves the HUD out of its captures. Performance offers its frame rate and memory.
A plugin declares a readout like this; it declares none unless it says so:

```swift
struct QueuePlugin: DebugDrawerPlugin {
    var title = "Queue"
    var icon = "tray.full"

    var body: some View {
        Text("3 jobs waiting")
    }

    var hud: Text? {
        Text("3 jobs")
    }
}
```

### Redacting sensitive values

Network's Copy cURL, Keychain's and UserDefaults' Copy Value and Cookies' Copy mask what the
drawer's redaction rules call sensitive, and the same values are masked on screen until the eye
button beside them reveals them. Revealing never changes a copy. The rules start as
`DebugDrawerRedaction.standard`: the `Authorization`, `Proxy-Authorization`, `Cookie` and
`Set-Cookie` headers, and keys containing `token`, `secret`, `password`, `session`, `auth` or
`apikey`. Add your own with one call:

```swift
#if DEBUG
DebugDrawer.shared.redact(
    headers: ["X-Api-Signature"],
    keys: ["pin"],
    jsonPaths: ["user.ssn", "cards.number"]
)
#endif
```

Header names and key patterns match case-insensitively; a key pattern matches header names, URL
query items, JSON keys at any depth, keychain accounts, services and labels, cookie names and
`UserDefaults` keys. A JSON path is dot-separated keys from the root, `*` matches any one key,
and arrays are transparent. Assign `DebugDrawer.shared.redaction = .none` to mask nothing.

### Bug reports

The drawer's header has a Create Report button that collects every plugin's data into one zip to
attach to a bug: a `summary.txt` (app, version, OS, device model, date and the list of files) and a
folder per plugin, named after its title. Every file is plain text, JSON, HAR or PNG, so it opens
without DebugDrawer, and the redaction rules mask what they call sensitive. Console adds its log
lines, Network an HTTP Archive (`network.har`) of the captured requests, App Info its facts,
UserDefaults the app's keys, Cookies the stored cookies and Screenshot the key window; Keychain
adds nothing. When the zip is ready, the drawer shows its name and a share button.

A plugin adds its own files by adopting `DebugDrawerReportContributor`; a plugin that doesn't is
left out. Pass what you add through the redaction it is handed:

```swift
struct CartPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
    var title = "Cart"
    var icon = "cart"

    var body: some View {
        Text("2 items")
    }

    func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        report.add(text: "2 items", named: "cart.txt")
        let checkout = Data(#"{"card":"4111","token":"t0k3n"}"#.utf8)
        report.add(jsonData: redaction.redacting(json: checkout), named: "checkout.json")
    }
}

#if DEBUG
DebugDrawer.shared.registerGlobal(CartPlugin())
let zip = try DebugDrawer.shared.createReport() // the same zip the button makes
#endif
```

The protocol, `DebugDrawerReport` and `DebugDrawerRedaction` exist in every configuration, so a
conformance compiles in release, where there is no drawer and no report.

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

// Play/Pause on the Siri Remote (tvOS), attached outside .debugDrawer() so it also closes it
ContentView()
    .debugDrawer()
    .onPlayPauseCommand { DebugDrawer.shared.toggle() }
```

### Keyboard

The app's own trigger opens the drawer (Ctrl-D in the example apps). While the drawer is open it
adds these shortcuts, on macOS and on iOS with a hardware keyboard; none of them exists while it
is closed, so they never open it or take a key from the app:

| Keys | Does |
|---|---|
| Cmd-K | Focuses the search field |
| Cmd-Option-Down / Cmd-Option-Up | Scrolls to the next or previous plugin's section and moves focus to its header |
| Escape | Clears the search field if it holds text, otherwise closes the drawer |

With keyboard navigation turned on (Full Keyboard Access on iOS, Keyboard navigation in macOS's
settings), Tab reaches every section header, and Space expands or collapses the section.

### Apple TV

On tvOS the library binds no remote button, so the app opens the drawer: from a button in its own
interface, or from a remote command it attaches, such as `.onPlayPauseCommand` or a long press
(`.onLongPressGesture`) on one of its views. Once open, the drawer takes focus, starting at the
plugin last used:

- Swiping or the arrows move focus through the header's buttons, the search field, each plugin's
  header and the controls inside an expanded plugin.
- Select on a plugin's header expands or collapses it; a long press shows its Pin, Move Up and
  Move Down actions.
- Select on the search field opens the keyboard; the results below the field are buttons.
- Menu clears the search if it holds text, otherwise closes the drawer, while focus is in it.

tvOS has no pasteboard and no share sheet, so `DebugDrawerCopyButton` draws nothing there and a
bug report names the zip's full path in the app's container instead of offering to share it. The
HUD stays at its corner, since tvOS has no drag.

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
| `DebugDrawer` | The drawer: its window, the plugin protocol and registry, the views plugins are built from, and release-build stand-ins |
| `DebugDrawerConsolePlugin` | `os_log` entries (stdout and stderr on macOS): level filter, search, auto-follow, copy |
| `DebugDrawerViewInspectorPlugin` | View borders by depth, alignment grid, click indicators, animation speed, SwiftUI render tracking, hierarchy snapshot |
| `DebugDrawerAccessibilityPlugin` | Runtime overrides of color scheme, Dynamic Type, layout direction, locale and the system accessibility settings SwiftUI exposes, each beside the system's value |
| `DebugDrawerPerformancePlugin` | Live FPS and memory with sparkline graphs |
| `DebugDrawerEnergyPlugin` | Battery level and charging, CPU load and thermal state |
| `DebugDrawerNetworkPlugin` | URLProtocol HTTP interception: method, URL, status, timing, headers, body, cURL export |
| `DebugDrawerDiskIOPlugin` | FileManager reads, writes, deletes and listings, flagging main-thread I/O |
| `DebugDrawerAppInfoPlugin` | Bundle, version, OS, memory, uptime, process, debugger, screen and reachability facts |
| `DebugDrawerUserDefaultsPlugin` | Browse, search, edit, copy and delete UserDefaults keys |
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
| `just lint` | SwiftLint and a11y-check over every first-party target |
| `just record-snapshots` | Every snapshot reference, re-recorded into the workspace |
| `just generate` | An Xcode project from the Bazel graph |
| `just run [macOS\|iOS\|visionOS\|tvOS]` | Build and launch the example app |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

MIT. See `LICENSE`.
