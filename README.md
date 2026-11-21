# DebugDrawer

A plugin-based debug drawer for macOS and iOS apps: a slide-in panel of debugging tools, each its
own library, so an app links only the tools it wants. Built for SwiftUI. Every entry point compiles
to a no-op outside `DEBUG`, so builds that ship to end users carry none of it.

## Installation

DebugDrawer requires Swift 6.3 and supports macOS 15 and iOS 17 or later. The core module,
`DebugDrawer` (the drawer, the plugin protocol and the shared views), also builds for visionOS 1
or later, where the drawer opens in an ornament beside the window rather than over it, and for
tvOS 17 or later, where the remote's focus moves through it (Apple TV, below), and for watchOS 10
or later, where it is a list of the plugins (Apple Watch, below). Every shipped plugin builds for
macOS and iOS. Analytics, Databases and Localization also build for visionOS, tvOS and watchOS,
and Color Vision and Reset App State for visionOS and tvOS; the others build for macOS and iOS
only, so an app on another platform registers plugins of its own. iOS includes Mac Catalyst: an
iOS app built for the Mac shows the iOS drawer in its window. The core and Analytics, Databases,
Localization, Screen Recording, Design Overlay, Color Vision and Reset App State build for Mac
Catalyst.

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/DebugDrawer", from: "0.1.3"),
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

Every public API exists in every configuration, so none of this needs `#if DEBUG`. Release builds
get stand-ins that do nothing: `DebugDrawer.shared` drops the plugins registered with it and never
opens, the plugins' `install*()` calls install nothing, and `.debugDrawer()` and
`.debugLocalPlugin()` return the view unchanged.

The drawer opens in a window of its own, above the app's sheets and alerts: on macOS a panel along
the trailing edge of the window, on iOS a window above the scene's, at 316 points wide or, where
the window is narrower than two of those (an iPhone in portrait), as wide as the window. Each
window's drawer opens and closes on its own; `toggle()`, `open()`, `close()` and `isOpen` act on
the key window's (on iPadOS, the scene with the key window, or else the foreground-active one), and
`toggle(in:)`
on the `NSWindow` or `UIWindowScene` it is given, attaching it first if it isn't yet. The plugin
registry is shared, but each window's drawer lists only the local plugins of its own views. A
UIKit or AppKit app without `debugDrawer()` attaches it with `DebugDrawer.shared.attach(to:)`,
passing each `UIWindowScene` or `NSWindow`, and gets the same drawer with every global plugin,
the HUD and the toasts. A section header's chevron, or the jump bar's menu, shows
one plugin alone at the panel's full height, and the back button returns to the list.

Such an app has no SwiftUI view for `.debugLocalPlugin()` to find its window from, so it ties a
local plugin to one window with `DebugDrawer.shared.registerLocal(_:in:)`, passing the `NSWindow`
or `UIWindowScene`: only that window's drawer lists the plugin, and closing the window (or
disconnecting the scene) removes it. It returns the token `unregisterLocal(id:token:)` takes to
remove it sooner.

```swift
final class CacheWindowController: NSWindowController {
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        DebugDrawer.shared.registerLocal(CachePlugin(), in: window)
    }
}
```

A local plugin is registered when its view appears and removed when it disappears, unless a newer
view has registered a plugin with the same `id` since. While the view is on screen the drawer shows
the plugin's latest value: `.debugLocalPlugin(UserPlugin(user: user))` shows the new user once
`user` changes. A plugin's `id` defaults to its type's fully qualified name (`MyApp.CachePlugin`),
so two modules' `CachePlugin`s both appear; registering a global plugin of another type under an
`id` already registered keeps the first and logs an error. The drawer saves its state (collapsed
sections, pins, the HUD, and plugin settings such as Deep Link's history) in a defaults suite of
its own, `<bundle identifier>.debugdrawer`, never among the app's standard defaults. A plugin
that needs a clean view of the app, as a screenshot does, runs its work in
`DebugDrawer.shared.performWhileHidden(drawer:_:)`: it hides the HUD, and every open drawer unless
`drawer` is false, runs the work once that has drawn, then shows them again.

### Building a plugin's view

Core has the views the shipped plugins are built from, so a plugin of your own looks like them:

| View | Shows |
|---|---|
| `DebugDrawerSection` | A group of rows with an optional heading and footer note |
| `DebugDrawerRow` | An icon, a title, details and a trailing accessory such as a toggle |
| `DebugDrawerKeyValueRow` | A label and a monospaced value; pass `redacted:` to mask a sensitive value until revealed |
| `DebugDrawerIssueRow` | An issue glyph, a title and its status, a monospaced subline and details |
| `DebugDrawerGaugeRow` | A measure with a bar meter, as Xcode's debug gauges |
| `DebugDrawerStackFrameRow` | A stack frame with an own-code or system badge |
| `DebugDrawerTypeBadgeRow` | A binary with a letter badge for its kind, its path and version |
| `DebugDrawerActionRow` | A plugin's push buttons, a destructive one at the trailing edge |
| `DebugDrawerIssueGlyph`, `DebugDrawerIssueCount` | A severity glyph, alone or with a count |
| `DebugDrawerUnreadDot` | The dot beside what hasn't been opened |
| `DebugDrawerCodeText`, `DebugDrawerCodeBlock` | A monospaced token cut in the middle, and a well of code or JSON |
| `DebugDrawerCopyButton` | A button that copies the text its closure returns when pressed |
| `DebugDrawerSparkline` | A line graph of recent samples |
| `DebugDrawerSearchableList` | A filter field above a scrolling list of rows; the plugin filters the rows |

Text, buttons, fields and colors take the drawer's look through `debugDrawerFont(_:)`,
`debugDrawerButtonStyle(_:)`, `debugDrawerTextFieldStyle()`, `debugDrawerForegroundStyle(_:)`
and `debugDrawerRowPadding()`. A plugin's `headerAccessory` puts a count, a summary or an action
at the trailing edge of its header row, shown while the plugin is closed too.

Each lays itself out for accessibility text sizes and labels itself for VoiceOver. They exist in
every configuration, so a plugin's body compiles in release, where they draw nothing.

### A plugin's lifecycle, and drawers of your own

A plugin can start work when a drawer adds it and stop it when the drawer removes it, and do the
costly part only while someone can see it. Each hook is optional and does nothing by default:

| Hook | Called |
|---|---|
| `install(in:)` | Once, as the drawer adds the plugin: `registerGlobal(_:)`, or a local plugin's view appearing |
| `didBecomeVisible(in:)` | As its content comes on screen: its section's body in an open drawer, the plugin shown alone, or its HUD readout; once, however many windows show it |
| `didBecomeHidden(in:)` | As the last of it leaves the screen (the drawer closed, the section collapsed, the readout unpinned), or as the drawer removes it while it is shown |
| `uninstall(from:)` | Once, as the drawer removes the plugin: `unregisterGlobal(id:)`, or a local plugin's view disappearing |

```swift
@MainActor
final class SocketMonitor {
    private(set) var isRunning = false
    var isSampling = false

    func start() { isRunning = true }
    func stop() { isRunning = false }
}

struct SocketPlugin: DebugDrawerPlugin {
    let monitor: SocketMonitor
    var title = "Sockets"
    var icon = "network"

    var body: some View {
        Text(monitor.isRunning ? "Watching sockets" : "Stopped")
    }

    func install(in drawer: DebugDrawer) { monitor.start() }
    func uninstall(from drawer: DebugDrawer) { monitor.stop() }
    func didBecomeVisible(in drawer: DebugDrawer) { monitor.isSampling = true }
    func didBecomeHidden(in drawer: DebugDrawer) { monitor.isSampling = false }
}
```

Each drawer owns the plugins registered with it. `DebugDrawer.shared` is the app's, which
`.debugDrawer()`, `attach(to:)` and the plugins' `install*()` calls use; `DebugDrawer()` makes
another with no plugins, apart from it, as a test does to check a plugin without touching the
shared drawer. `DebugDrawer(defaults:)` also keeps what it saves (pins, order, the HUD) in a
`UserDefaults` suite of its own.

```swift
let monitor = SocketMonitor()
let drawer = DebugDrawer()

drawer.registerGlobal(SocketPlugin(monitor: monitor)) // install(in:): the monitor starts
drawer.unregisterGlobal(id: SocketPlugin(monitor: monitor).id) // uninstall(from:): it stops
```

Every shipped plugin starts its work in `install(in:)` and undoes it in `uninstall(from:)`, so
`unregisterGlobal(id:)` takes a plugin out of the app as well as out of the drawer. Network, Disk
I/O, Location and View Inspector give each method they swizzled its original implementation back
and unregister the URL protocol; Accessibility clears its overrides; the plugins that watch the
app stop their observers, handlers and threads and let go of what they captured. What a plugin
saved to disk or to `UserDefaults` (mock rules, earlier sessions, reports, settings) stays for the
next install, and installing again starts it all over. Work a plugin does for every app window is
counted by drawer: it stops once the last drawer holding the plugin removes it. A method other code
swizzled again on top of the plugin's can't be put back without breaking that code, so it is left
in place and calls straight through, recording nothing, until the plugin is installed again.

When two drawers hold Network, Console or View Inspector, the one that installed it last gets
what it captures (requests, log lines, render counts), and Network's mock rules and conditions
come from that drawer's plugin; once that drawer removes the plugin, the one before it captures
again. Location works the same way: `installLocation()` on a drawer of your own gives it a
simulator of its own, its switch and coordinate kept in that drawer's defaults, and the app's
location managers get the locations of the drawer that installed it last.
`ScreenRecording.install(in:)` gives a drawer its own recorder, list and Show Touches setting. An
app that uses only the shared drawer sees no difference.

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
message and how many posts it stands for; a post while the drawer is open is dropped. The toast goes
away by itself `DebugDrawer.toastLifetime` (6) seconds after its last post, and stays while the
pointer is over it or VoiceOver's focus is on it. A plugin's badges and toasts go to each drawer
that holds it (`DebugDrawer.shared`, or a `DebugDrawer()` of your own), and to `shared` while none
does. The counts of Analytics, Crash Reports, Hangs, Leaks and MetricKit badge only the drawers that
installed the plugin: each shows the count as it installs the plugin and clears it as it removes it.
To quiet a plugin that posts too often, choose Silence Notices from its section header's context menu: its
badge and toast go away, what it posts afterwards is dropped, and a crossed-out bell marks its
header until Allow Notices. The choice is remembered across launches;
`DebugDrawer.shared.setNoticesMuted(_:forPlugin:)` and `isNoticesMuted(forPlugin:)` do the same
from code. In release builds these calls compile and do nothing.

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

A plugin can offer a compact readout for the floating HUD, which stays on screen while the drawer is
closed. Choose Show in HUD from a plugin's context menu in the drawer to pin its readout, and Unpin
from the readout's own context menu (touch and hold it, or Control-click it on the Mac) to take it
off; drag the HUD anywhere in the window. Only the HUD itself takes touches; the rest of the window
reaches the app. The pinned readouts and the HUD's position are remembered across launches, and the
Screenshot plugin leaves the HUD out of its captures. Performance offers its frame rate and memory,
Network its active conditioning profiles, Screen Recording a Record button that becomes the elapsed
time and Stop, and Design Overlay and Color Vision a switch of their own.
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

Network's Copy cURL, Keychain's and UserDefaults' Copy Value, Cookies' Copy and Analytics' Copy
JSON mask what the drawer's redaction rules call sensitive, and the same values are masked on
screen until the eye button beside them reveals them. Analytics installed in a `DebugDrawer()` of
your own masks by that drawer's rules. Revealing never changes a copy. The rules start as
`DebugDrawerRedaction.standard`: the `Authorization`, `Proxy-Authorization`, `Cookie` and
`Set-Cookie` headers, and keys containing `token`, `secret`, `password`, `session`, `auth` or
`apikey`. Add your own with one call:

```swift
DebugDrawer.shared.redact(
    headers: ["X-Api-Signature"],
    keys: ["pin"],
    jsonPaths: ["user.ssn", "cards.number"]
)
```

Header names and key patterns match case-insensitively; a key pattern matches header names, URL
query items, JSON keys at any depth, keychain accounts, services and labels, cookie names and
`UserDefaults` keys. A JSON path is dot-separated keys from the root, `*` matches any one key,
and arrays are transparent. Assign `DebugDrawer.shared.redaction = .none` to mask nothing.

### Bug reports

The drawer's header has a Create Report button that collects every plugin's data into one zip to
attach to a bug: a `summary.txt` (app, version, OS, device model, date and the list of files) and a
folder per plugin, named after its title. Every file is plain text, JSON, HAR, PNG or a QuickTime
movie, so it opens without DebugDrawer, and the redaction rules mask what they call sensitive.
Console adds its log lines (and an earlier launch's, `console-previous.txt`), Network an HTTP Archive (`network.har`) of the captured requests, App
Info its facts, UserDefaults the app's keys, Cookies the stored cookies, Screenshot the key window
and Screen Recording the newest recording; Keychain adds nothing. When the zip is ready, the drawer shows its name and a share button.

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

DebugDrawer.shared.registerGlobal(CartPlugin())
let reports = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
let zip = try DebugDrawer.shared.createReport(in: reports) // the same zip the button makes
```

The protocol, `DebugDrawerReport` and `DebugDrawerRedaction` exist in every configuration, so a
conformance compiles in release, where there is no drawer and `createReport(in:)` throws
`DebugDrawerReport.WriteFailed`.

#### Sending reports

To send a report straight to your team (an internal endpoint, an issue tracker's webhook), give
the drawer an uploader. It is handed the zip's URL and reports the fraction sent; the drawer then
shows a send button beside every finished report, the upload's progress, and the uploader's error
with a Retry button when it fails. The zip stays on disk until the system clears the temporary
directory, so a failed upload can be retried or shared instead. Until an uploader is set there
is no send button, and DebugDrawer itself never touches the network.

```swift
struct TeamReportUploader: DebugDrawerReportUploader {
    let endpoint: URL

    func upload(_ archive: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: archive)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        progress(1)
    }
}

DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)
```

`DebugDrawerReportUploader` exists in every configuration too, so the uploader compiles in
release, where nothing calls it.

### Installing the shipped plugins

Each plugin installs itself with one call at startup. All of them:

```swift
DebugDrawer.shared.installConsole()
DebugDrawer.shared.installViewInspector()
DebugDrawer.shared.installAccessibility()
DebugDrawer.shared.installPerformance()
DebugDrawer.shared.installEnergy()
DebugDrawer.shared.installNetwork()
DebugDrawer.shared.installDiskIO()
DebugDrawer.shared.installScreenshot()
DebugDrawer.shared.installAppInfo()
DebugDrawer.shared.installKeychain()
DebugDrawer.shared.installLocation()
DebugDrawer.shared.installLoadedLibraries()
DebugDrawer.shared.installDeepLink()
DebugDrawer.shared.installCookies()
DebugDrawer.shared.installLaunchTime()
```

Each call needs its plugin's module imported (`import DebugDrawerConsolePlugin`, and so on).
Tweaks takes the settings it shows and Feature Flags the adapter it reads, and Crash Reports,
Hangs, Leaks, MetricKit, Permissions, Notifications, Background Tasks, Analytics, Databases, File
Browser, UserDefaults, Localization, Screen Recording, Design Overlay, Color Vision and Reset App
State install through a type of their own, so each has a section of its own, after Network's mocks
and conditions.

### The plugins with nothing to configure

These need only their install call:

- **Performance** counts the frame rate from a display link on the main run loop, so a blocked main
  thread shows as dropped frames and a lower rate, and shows the memory footprint with its peak
  for the process's life, CPU use per thread (the busiest eight until Show All) and a graph of the
  last 60 samples, one a second. On iOS, Simulate Memory Warning posts
  `UIApplication.didReceiveMemoryWarningNotification` to the app's observers. It samples only while
  a drawer shows its view or its HUD readout, from the plugin's `didBecomeVisible(in:)` to its
  `didBecomeHidden(in:)`; the graphs keep their samples while it is hidden and carry on from them.
- **Energy** shows the battery's level, whether it is charging, the power source, the thermal
  state and this process's CPU load (not Xcode's Energy Impact, which also weighs the GPU, network,
  location and wakeups), with two minutes of history. It samples once a second while a drawer shows
  its view, or between the app's own `EnergyMonitor.shared.start()` and `stop()`. A Mac without a
  battery shows no Battery section.
- **Screenshot** captures the app's key window: on macOS its content, To Desktop as a PNG named
  after the app and the time, or To Clipboard; on iOS the window with its sheets and alerts, to the
  clipboard. The drawer is a window of its own, so it is never in the capture; the HUD is hidden
  while the capture is taken, and the drawer is closed for it unless its switch says otherwise. A
  sandboxed Mac app that can't write to the Desktop gets a save panel instead.
- **Keychain** lists the generic and internet passwords, certificates and keys the app can read,
  each with every attribute the keychain returns, filtered by access group and text. A password's
  value is read when its detail opens; a key's or certificate's data never is. Generic passwords
  can be added and edited, on this device only, and any item deleted. On the Mac it reads the data
  protection keychain, never the login keychain (What the plugins need, below).
- **Loaded Libraries** lists every image loaded into the process when its view appears, grouped as
  App, Third-Party (frameworks embedded in the app) and System, each with its path, UUID, load
  address and a framework's version, with a filter and Copy List.
- **HTTP Cookies** lists `HTTPCookieStorage.shared`'s cookies by domain, read when its view appears
  and on Refresh, searched by name or domain; a row expands to its value, domain, path, store,
  flags and expiry. Where WebKit exists (macOS and iOS; not tvOS or watchOS), it also lists the
  cookies web views keep in `WKWebsiteDataStore.default().httpCookieStore`, each row marked
  URLSession or WKWebView by the store it is in. Each can be deleted from its own store, and Delete
  All, after asking in place, deletes the cookies the filter shows; the count and Copy follow the
  filter too. Values are masked as the redaction rules say, which by default mask every cookie.
- **Launch Time** measures from the process's start (from the kernel) to the `installLaunchTime()`
  call, as pre-main, and from there to the first time the main run loop goes idle, as the first
  frame, so call it as early as the app can: in `App.init` or
  `application(_:didFinishLaunchingWithOptions:)`.
- **Accessibility** overrides, for the views under `.debugAccessibilityOverrides()` (Optional
  modifiers, below), the color scheme, Dynamic Type size, layout direction, the locale (when the
  app has localizations) and the accessibility settings SwiftUI reads: Reduce Motion, Increase
  Contrast, Bold Text, Reduce Transparency, Differentiate Without Color and Invert Colors, each of
  those beside the system's value. Reset All clears them; they last until the app quits. A release
  build gets none of this; a sidecar can override Dynamic Type, Increase Contrast and Reduce
  Motion there instead ("Accessibility overrides in production", below).
- **View Inspector** outlines every AppKit or UIKit view in the app's windows, colored by its
  depth, draws the alignment grid over the views `.debugGrid()` is applied to and a ripple where
  each click or touch lands, makes animations up to ten times slower, and lists the key window's
  view hierarchy with each view's class and accessibility label. The outlines, grid and ripples are
  drawn in a window of the drawer's own over the app's, which takes no clicks or touches, so they
  change no view or layer of the app's and don't appear in the app's own snapshots or screenshots
  of its windows. A view's outline stops where something the app shows covers it: a sheet, form
  sheet or popover presented over it, an opaque child window, or an opaque window above its own.
  Slow Animations divides the speed of each window's root layer and gives back the
  speed it had at Normal. Its render counts follow below (View Inspector).

### Deep links: URLs, universal links and user activities

Opening an https URL goes to the browser, so a universal link, a Handoff or a Spotlight result
can't be tested by opening a URL. The Deep Link Tester continues one in the app instead, as the
system does: an https URL in the field is sent as an `NSUserActivity` of type
`NSUserActivityTypeBrowsingWeb` with that `webpageURL`, and Activity mode sends an activity of the
app's own type with a userInfo of strings, numbers and Booleans. Sent activities are listed apart
from the URLs opened, and a tap puts one back in the form.

Pass the code that routes the app's own URLs as `openURL`, and an opened URL goes to it rather
than to the system, so it never reaches the browser or another installed copy of the app. It
returns whether it handled the URL, and the plugin shows which. A SwiftUI app's
`onContinueUserActivity` has no public entry point either, so a SwiftUI app also passes the code
that handles an activity:

```swift
import DebugDrawerDeepLinkPlugin
import Foundation

/// The app's router: `onOpenURL` and `onContinueUserActivity` hand it the links the system opens.
@MainActor
final class Router {
    private(set) var path: [String] = []

    func handle(_ activity: NSUserActivity) {
        if let url = activity.webpageURL {
            path.append(url.path)
        }
    }

    func open(_ url: URL) -> Bool {
        guard url.scheme == "myapp" else { return false }
        path.append(url.path)
        return true
    }
}

let router = Router()

DebugDrawer.shared.installDeepLink(
    presets: DeepLinkPreset.bundleURLSchemes + [DeepLinkPreset("Order 42", url: URL(string: "myapp://orders/42")!)],
    continueUserActivity: router.handle,
    openURL: router.open
)
```

Presets lists one URL for each scheme the app's Info.plist declares under `CFBundleURLTypes`
(`DeepLinkPreset.bundleURLSchemes`) unless the app passes its own; with neither, it says how to
add some.

Without `openURL`, the system opens the URL as it does a tapped link, and the plugin says when it
couldn't and why; on the Mac a scheme the app declares opens in the running copy of the app.
Without `continueUserActivity`, an activity goes where the system sends it in a UIKit or AppKit
app: on iOS, the first window scene delegate with `scene(_:continue:)`, else the app delegate's
`application(_:continue:restorationHandler:)`; on the Mac, the app delegate's. When the app has
none of these, the plugin says so rather than dropping the activity.

### App Info: which build is this?

App Info answers QA's first question with more than the version. Its Build section shows the
version and build number and, when the app supplies them, the commit, branch and CI build number it
was built from. Pass them at install, or write them into the app's Info.plist (from a CI script, say)
under `DebugDrawerGitCommit`, `DebugDrawerGitBranch` and `DebugDrawerCIBuildNumber`; a value passed
at install wins over the plist's:

```swift
DebugDrawer.shared.installAppInfo(buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "release/2.4"))
```

The Build section also shows the bundle identifier. Runtime follows, with the memory footprint,
uptime, process ID, architecture and argument count, then Environment: the OS, the sandbox (on the
Mac), whether a debugger is attached, the active processors, physical memory, the screen, the
network path (Wi-Fi, cellular, Ethernet or offline) and when the process started. The footprint
and uptime are read again every 2 seconds while a drawer shows the plugin, and not at all while
none does; the network path is watched from the plugin's first use, so Copy Info and the bug report
know it with the drawer closed.
Provisioning then shows the embedded profile (`embedded.mobileprovision` on iOS,
`embedded.provisionprofile` on the Mac): its name, team, creation and expiry dates, with a warning
once it has expired, and how many devices it names. A simulator, App Store or unprovisioned Mac
build has none, and says None. Entitlements lists what the app runs with, the common ones by name
(associated domains first, then app groups, keychain access groups, the sandbox, get-task-allow)
and the rest by key: on the Mac from the code signature, on a simulator from the entitlements linked
into the executable, and on a device from the profile, which gives what it allows. Copy Info and the
bug report's `App Info/app-info.json` carry all of it, entitlements by key.

### Console sessions: logs from earlier launches

The lines logged during a launch, or just before a crash, are kept on disk, so the next launch can
show them; the unified log of the current process holds no earlier launch's lines on iOS. Each
line is written as it is captured, as logged: log text has no keys for the redaction rules to
match, so the Console shows, copies and keeps it unmasked. A launch's session is a file of JSON
Lines in Application Support, in the app's folder under `DebugDrawer/ConsoleSessions`: a header
with the start, the app's version and the process, written at install, then one line per log line, with its time, level, source,
os_log subsystem and category (left out when empty) and text, appended as it comes, so a crash mid-write costs at most the line being written, which is
skipped on reading. Writing happens on a queue of its own, in batches, never on the main actor. By
default 5 earlier sessions are kept in at most 20 MB; both are set at install:

```swift
import DebugDrawerConsolePlugin

DebugDrawer.shared.installConsole(sessions: ConsoleSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
```

At launch the oldest sessions beyond `maxSessions` are deleted, then the oldest until the rest fit
in `maxBytes`, which is checked again as the current session grows. The current session is never
deleted; a line that would take it alone past `maxBytes` isn't written. `ConsoleSessionPersistence.off`
writes nothing and deletes what earlier launches kept. To keep sessions somewhere else, pass a
`storage` of your own, a `ConsoleSessionStorage` (append, list, read and delete).

The console reads the app's os_log lines from its unified log every two seconds, so a crash or a
kill can come before it has read the last ones. On macOS, where the app may read the system's log
(`OSLogStore(scope: .system)`; an app outside the App Sandbox, run by an administrator, may), the
next launch reads those lines from it and adds them to the end of the earlier session (a launch
that starts before the system has taken in a crashed process's last lines misses them). While the
Mac is busy, one read of the system's log can miss a line it holds, so the next launch reads it
again, up to four times, until a read holds the session's own last os_log line and finds nothing
the reads before it lacked; it keeps every line any read found. That takes one or two seconds a
read, which listing the earlier sessions waits for, and a line every read missed is still lost.
Elsewhere a session keeps what its launch read. A session that kept no line and missed none is
deleted at the next launch.

In an app signed with the App Sandbox the system's log doesn't open: `OSLogStore(scope: .system)`
throws "Connection to logd failed" (`OSLogError` 10), so the lines are lost as on iOS. A sandboxed
app's debug build can read it with these temporary exceptions in its entitlements, which App
Review doesn't accept, so keep them out of what you ship:

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>com.apple.logd</string>
    <string>com.apple.logd.admin</string>
    <string>com.apple.logd.events</string>
</array>
<key>com.apple.security.temporary-exception.files.absolute-path.read-only</key>
<array>
    <string>/private/var/db/diagnostics/</string>
    <string>/private/var/db/uuidtext/</string>
</array>
```

On iOS, Mac Catalyst included, the os_log lines of up to the last two seconds before a crash are
lost. A process there reads only its own log (`OSLogStore(scope: .currentProcessIdentifier)`),
and at the next launch that holds none of the earlier process's lines, though the system still
has them. Nothing public reads another process's log on iOS or tells the app of an os_log call as
it is made, and a crash's signal handler can't read the log safely, so the plugin doesn't try. A
line that has to outlive a crash can go through `ConsoleLogSink` (see "Console: your own logger"):
its lines are written to the session as they arrive, not every two seconds. A line logged through
both `os.Logger` and the sink shows twice. On the simulator the Mac can show the lost lines for a
while after the crash: `xcrun simctl spawn booted log show --last 5m --predicate 'process == "YourApp"'`.

While an earlier session is kept, the console offers Captured and Previous. Previous shows the
newest earlier session, read-only, with a menu of the others by start and size, the app version
that wrote it and how many lines it holds; the level filter, search, mutes, time range and Copy All
work on it as on the captured lines. Delete deletes it and Delete All Sessions deletes every earlier one. The bug
report adds the newest earlier session as `console-previous.txt`.

### Console filters: subsystems, categories, patterns and time

Each os_log line shows its subsystem and category, short and quiet, before its text (`feed/networking`
for `com.example.feed`'s `networking`). A line's context menu, or its edit menu on iOS, mutes its
subsystem or its category, or shows the lines from it on; More offers the same mutes for every
subsystem and category shown, Copy All, and a time range (the last 1, 5 or 15 minutes before the
newest line). Mutes are kept across launches in the app's folder in Application Support, under
`DebugDrawer/Console/muted.json`. While they hide lines, a note under the log says how many, with Show
and Unmute; a time range says so the same way. The `.*` toggle beside the search field reads the
search as a regular expression (`NSRegularExpression`, ignoring case); while the text isn't one, the
field says so and the list keeps the last valid search.

### Console: Apple's framework logs

Apple's frameworks log debug and info lines fast enough to push the app's own lines out of the
Console's 2,000 within seconds, so the Console leaves out the debug and info lines of every
subsystem starting with `com.apple.`. Their notice, error and fault lines are kept, as is every line
of the app's own, stdout and stderr. To keep Apple's debug and info lines too, install with
`installConsole(includeSystemDebugLogs: true)`.

### Console: your own logger

The Console captures the process's os_log entries and, on macOS, its stdout and stderr; on iOS
it captures neither stream, as redirecting them would cut Xcode's debugger off from them. A logger
that writes through swift-log, CocoaLumberjack or code of the app's own doesn't reach os_log, so
the Console can't capture its lines from there. Send them to `ConsoleLogSink` instead,
from any thread:

```swift
import DebugDrawerConsolePlugin

ConsoleLogSink.log(
    level: .error, message: "Payment declined", metadata: ["order": "1042"],
    subsystem: "com.example.shop", category: "checkout"
)
```

The line shows its metadata after its text as quiet `key=value` fields (`order=1042`), under it at
accessibility text sizes, and the search matches metadata keys and values as it does the text. The
subsystem and category show and mute like an os_log line's; Copy All, the bug report and the
sessions on disk keep the metadata. `ConsoleLogSink` exists in release builds too, where `log` does
nothing and evaluates none of its arguments, so the bridge needs no `#if DEBUG`.

The plugin depends on no logging package; the app writes the bridge. For swift-log, a `LogHandler`
that passes each entry on, with the logger's label as the subsystem and the module that logged it
as the category:

```swift
import DebugDrawerConsolePlugin
import Logging

/// Sends each swift-log entry to the Console: the label as the subsystem, the module that logged
/// it as the category, and the handler's and the entry's metadata as key/value fields.
struct ConsoleLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level = .trace
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let merged = metadata.merging(event.metadata ?? [:]) { _, logged in logged }
        ConsoleLogSink.log(
            level: ConsoleLogSink.Level(event.level),
            message: event.message.description,
            metadata: merged.mapValues(\.description),
            subsystem: label,
            category: event.source
        )
    }
}

extension ConsoleLogSink.Level {
    init(_ level: Logger.Level) {
        switch level {
        case .trace, .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning, .error: self = .error
        case .critical: self = .fault
        }
    }
}

LoggingSystem.bootstrap { label in
    MultiplexLogHandler([StreamLogHandler.standardError(label: label), ConsoleLogHandler(label: label)])
}
```

### Network: what it captures

`installNetwork()` registers a URL protocol for `URLSession.shared` and adds it to every
`URLSessionConfiguration`, so the log shows the http and https requests of the shared session and
of the app's other sessions, those of networking libraries built on `URLSession` included.

The plugin sends each request it captures on a session of its own, made from a copy of the app
session's configuration, and hands what it hears to the app's task. So the request gets the app
session's cookie storage, cache, credentials, extra headers, timeouts, proxy and TLS settings, and
an ephemeral session's cookies and cached responses stay its own. Redirects and authentication
challenges go to the app's task, so the app's session delegate decides them as it does without the
plugin: a redirect it refuses isn't followed, and a delegate that pins certificates or answers with
a client certificate gets the server's challenge, and its answer is used. The request goes out as
the app made it, with no header added; a body the app streams is sent with its length
(`Content-Length`) rather than in chunks.

What the plugin doesn't capture, or can't keep as it was:

- Requests that don't go through a URL protocol aren't seen: background sessions' (the system
  loads them outside the app), web views' (`WKWebView`), AVFoundation's streaming (`AVPlayer`),
  Network.framework's connections and `URLSession` stream tasks. WebSocket tasks don't go through
  it either; their frames are recorded on the tasks themselves (Network WebSockets, below).
- Requests to a host `installNetwork(bypassing:)` names aren't seen (Network: apps that pin
  certificates, below).
- A session made before `installNetwork()` is captured, but the plugin can't learn its
  configuration, so its requests are sent with the default one: the shared cookie storage, cache
  and credentials. Install at startup.
- The app's session delegate isn't told of upload progress (`didSendBodyData`) or of waiting for
  connectivity, which a URL protocol has no way to report.

The log keeps the newest 200 requests (set
`NetworkStore.shared.capacity` for another number) and the first megabyte of each request and
response body, marked truncated with its full size beyond that; `installNetwork(bodyLimit:)` takes
another limit. The server and the app always get the whole body.

### Network: apps that pin certificates

An app whose session delegate pins its server's certificate or key can count on these, with the
Network plugin installed:

- **The app's pin decides.** The plugin's session hands every TLS challenge to the app's task, so
  the app's session delegate is asked about the server's trust as it is without the plugin, and its
  answer is used. The plugin never trusts a server on its own. This holds for a session made before
  `installNetwork()` too, which is sent with the default configuration but whose challenges still
  go to its own delegate.
- **A refused pin sends nothing.** When the delegate cancels the challenge, the connection ends in
  its TLS handshake: the request line, the headers (an `Authorization` token among them) and the
  body never reach the server, and the app's task fails with `URLError(.cancelled)`, as it does
  without the plugin.
- **A stream held open passes through.** Server-Sent Events and other long responses reach the app
  as they arrive, while the response is still open, and the log keeps only the first `bodyLimit`
  bytes however long the stream runs.

What the tests don't cover:

- **ATS pinning** (`NSPinnedDomains` in the app's Info.plist). The system reads it for every
  `URLSession` in the app's process, the plugin's included, but no test shows the plugin's requests
  are refused alike: ATS reads the key from the app's own Info.plist, which a test runner doesn't
  have, and checks a pin only on top of the system's trust, which a test server's self-signed
  certificate on a loopback address never gets.
- **Pinning libraries.** Alamofire's `ServerTrustManager` and TrustKit's delegate swizzling check
  the certificate in the session delegate, which gets the challenge as above, but neither library
  is tested here.

To keep a host out of the plugin entirely, bypass it:

```swift
import DebugDrawerNetworkPlugin

DebugDrawer.shared.installNetwork(bypassing: ["api.example.com"])
```

The requests to a bypassed host, and to its subdomains, never reach the plugin's URL protocol: the
app's session sends them itself, with its own delegate, as if the plugin weren't installed. They
aren't logged, mocked, conditioned or offered for resending, and their WebSocket tasks aren't
recorded; the app's other traffic is captured as usual. A host is matched as an ignored one is
(below): on whole labels, ignoring case, and an IP address matches only itself. Each call replaces
the hosts an earlier one bypassed, and text that isn't a host traps, so a typo can't leave a pinned
host intercepted. Where `ignoring:` only hides requests from the list, `bypassing:` keeps the plugin
out of them.

### Network mocks: canned responses without changing the server

The Network plugin can answer requests itself. A mock rule matches requests by method, host, path
and query items, and answers with a status, headers and a body, so a developer can try an error,
an empty list or an endpoint the server doesn't have yet. Rules are made in the drawer (Add Mock,
or Mock This on a captured request, which starts from its method, host, exact path and the
response the server sent), or passed to `installNetwork(mocks:)`:

```swift
import DebugDrawerNetworkPlugin

let outage = NetworkMockRule(
    id: UUID(uuidString: "3F2B8E1C-0D4A-4B7E-9C61-5A2D7E8F9B10")!,
    name: "Orders outage",
    matcher: .init(methods: ["GET", "POST"], host: .wildcard("*.example.com"), path: .wildcard("/v1/orders/**")),
    response: .init(status: 503, body: .text(#"{"error":"maintenance"}"#), contentType: "application/json")
)
DebugDrawer.shared.installNetwork(mocks: [outage])
```

A host or path is matched exactly, by a wildcard or by a regular expression (`NSRegularExpression`),
and a wildcard or regex must match the whole of it: in a host `*` matches within one label
(`*.example.com` matches `api.example.com`) and `**` across labels; in a path `*` matches within
one segment (`/users/*`) and `**` across segments (`/users/**`). Hosts ignore case; paths are
compared percent-decoded. The rules are tried in the order the drawer lists them, and the first
that is on and matches answers, with no request sent; `Content-Length` is always the body's length.
A request no rule matches reaches the network unchanged. Rules apply only once `installNetwork()`
has run. A production build gets none of this; a sidecar can set rules there for its session,
through the sessions the app configures, as "Network mocks in production" below shows.

The Mocks section, below the request log, lists each rule with a switch, its methods, pattern and
status; selecting one offers Edit, Move Up, Move Down and Delete, and the plugin's header counts the
rules that are on. The editor takes the methods, the host's and path's patterns (an invalid regex
says why below its field), query items, the status, a content type, headers, and a body as text or a
file, which is copied into the app's storage. A rule passed to `installNetwork(mocks:)` is added
once, by its `id`, so the drawer's edits to it last. Rules are saved as JSON in Application Support,
in the app's folder under `DebugDrawer/NetworkMocks`, and loaded by `installNetwork()`. A request a
rule answered shows Mocked in the log, its detail names the rule, and the bug report's `network.har`
says which rule answered it.

### Network conditions: slow and failing networks per host

The Network plugin can also make a host slow or unreliable, without the Network Link Conditioner
and without slowing the rest of the device. A conditioning profile applies to one host (matched
exactly, by a wildcard or by a regex, as a mock rule's host is) or to every host, and adds a
latency, caps the bandwidth the response's body arrives at, and fails a share of the requests
with a timeout (`URLError(.timedOut)`), no connection (`URLError(.notConnectedToInternet)`) or an
HTTP 500. Profiles are made in the drawer (Add Condition, with presets for 3G, Edge and a lossy
network), or passed to `installNetwork(conditions:)`:

```swift
import DebugDrawerNetworkPlugin

let slowImages = NetworkConditionProfile(
    id: UUID(uuidString: "8C4F2A61-7B3D-4E59-A1C8-2D6E9F0B3A47")!,
    name: "Slow images",
    host: .wildcard("*.cdn.example.com"),
    latency: .seconds(2),
    bandwidth: 50_000
)
let paymentsOffline = NetworkConditionProfile(
    id: UUID(uuidString: "5E9B1D73-2C48-4F6A-B0E5-7A3C8D1F2E96")!,
    name: "Payments offline",
    host: .exact("payments.example.com"),
    failureRate: 100,
    failure: .notConnectedToInternet
)
DebugDrawer.shared.installNetwork(conditions: [slowImages, paymentsOffline])
```

The bandwidth is in bytes a second and the failure rate in percent. The first profile that is on
and matches a request's host applies; a request to a host no profile matches is untouched. A
conditioned request waits out the latency first, then fails (each request rolls afresh), or gets
its answer: a mock rule's, when one matches, or the server's, read whole and then delivered no
faster than the cap. Uploads aren't capped. The Conditions section, below Mocks, lists each
profile with a switch and what it does, and while any is on the plugin's header counts them ("1
active"); pin the Network plugin to the HUD to see which with the drawer closed ("Slow images
active"). A conditioned
request shows Conditioned in the log, its detail names the profile and what it did ("Delayed
2,000 ms · Failed: timeout"), and `network.har` says so too. Profiles are saved beside the mock
rules, in `conditions.json`, and a profile passed to `installNetwork(conditions:)` is added once,
by its `id`.

### Network replay: resend a captured request

A captured request's detail offers Resend, which sends it again as it was, and Edit and Resend,
which opens its method, URL, headers and body to change first (the URL must be http or https with a
host, and a GET or HEAD can't carry a body). A POST, PUT, PATCH, DELETE or any other method that
isn't safe asks before it is sent, in place under the buttons; a GET, HEAD, OPTIONS or TRACE is sent
at once. The resent request goes through the plugin like any the app makes, so a mock rule can
answer it and a conditioning profile can slow it, and it uses the app's default session
configuration (its cookies and cache). It shows in the log as a new request marked Replay, whose
detail names the request it resent ("Replay of GET /v1/greeting at 10:42:05") with a button that
selects it; the original says how often it was resent. A resend that gets no answer says why in the
original's detail, and `network.har` notes each replay's original. The mark stays inside the
process: no header is added, so the server sees exactly the request shown. There is nothing to
install beyond `installNetwork()`.

### Network archives: HAR export and import

The Network log exports as an HTTP Archive (HAR 1.2), the file Charles, Proxyman and browsers'
network inspectors read. Export All shares every request the log holds; while the status filter or
the filter text hides some, the button reads Export Shown and the file holds only the requests
listed. The file has each request's start, time, method, URL, headers, query, cookies and body, and
the response's status, headers, cookies and body (in base64 when it isn't text), with timings where
the request was measured and `-1` for sizes the plugin doesn't know. The redaction rules apply as
they do to Copy cURL: masked headers, query items and JSON body values, and the cookies whose
names the rules match, in the cookie lists and in the `Cookie` and `Set-Cookie` headers.

Import HAR… opens a `.har` or `.json` file and shows its requests in the log in place of the
captured ones, under Captured and Imported, which switch between the two. Archives from Chrome
DevTools, Charles and Proxyman read as well as the drawer's own: fields they leave out are unknown,
and fields of their own are ignored. Imported requests are read-only: their detail offers Copy cURL
and Mock This, which makes a mock that answers like the archive's response, but not Resend. Clear
removes the imported file and shows the captured requests again. A file that isn't a HAR 1.x
archive is refused with the reason under the buttons ("The file isn't JSON.") and leaves the log as
it was. The bug report's `network.har` holds the captured requests and WebSocket connections only;
an earlier launch's are in `network-previous.har` (Network sessions, below).

### Network WebSockets: frames sent and received

`URLSessionWebSocketTask` traffic never passes through a URL protocol, so `installNetwork()` also
records it on the tasks themselves: each task a session makes from then on is a connection in the
WebSockets section, under the request log, with WS, whether it is open, closed or failed, its path
and how many frames it carried. Its detail shows when it opened, the subprotocols offered, who
closed it with which close code and reason (from `cancel(with:reason:)`, or the server's close
frame), or the error it failed with, then its frames, the latest first: ↑ for sent, ↓ for
received, the time to the millisecond, the kind and size, and a preview, the start of a text frame
or the first 16 bytes of a binary one in hex (`00 01 02 … 0f …`). Pings and their pongs are listed
too. The async and completion-handler forms of `send` and `receive` are both recorded, and the app
gets exactly the messages and errors it would without the plugin.

A connection keeps its latest 500 frames, and the log its latest 50 connections; each frame keeps
its first 16 KB. Copy Frames and the HAR export (Chrome DevTools' `_webSocketMessages`) mask the
URL's query items and JSON text frames as the redaction rules say; a text frame larger than 16 KB
is copied and exported without its text, which can't be masked. There is nothing to install
beyond `installNetwork()`; socket libraries that don't use `URLSessionWebSocketTask` aren't seen.

### Network sessions: requests from earlier launches

The requests made during launch, or just before a crash, are kept on disk, so the next launch can
show them. Each request is written as it completes, and each WebSocket connection as it ends, with
the redaction rules applied first, so a masked header, query item or JSON value never reaches the
disk. A launch's session is a file of JSON Lines in Application Support, in the app's folder under
`DebugDrawer/NetworkSessions`: a header with the start and the app's version, then one HAR 1.2
entry per line, appended as it comes, so a crash mid-write costs at most the line being written,
which is skipped on reading. Writing happens on a queue of its own, never in the URL protocol's
callbacks or on the main actor. By default 5 earlier sessions are kept in at most 20 MB; both are
set at install:

```swift
import DebugDrawerNetworkPlugin

DebugDrawer.shared.installNetwork(sessions: NetworkSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
```

At launch the oldest sessions beyond `maxSessions` are deleted, then the oldest until the rest fit
in `maxBytes`, which is checked again as the current session grows. The current session is never
deleted; a request that would take it alone past `maxBytes` isn't written. `NetworkSessionPersistence.off`
writes nothing and deletes what earlier launches kept. To keep sessions somewhere else, pass a
`storage` of your own, a `NetworkSessionStorage` (append, list, read and delete).

While an earlier session is kept, the log offers Captured and Previous (and Imported, while a file
is). Previous shows the newest earlier session, with a menu of the others by start and size, the
app version that wrote it and how many requests it holds. Its requests are read-only, as imported
ones are: Copy cURL and Mock This, but not Resend. Export All exports it as a HAR file, Delete
deletes it and Delete All Sessions deletes every earlier one. The bug report adds the newest
earlier session as `network-previous.har`. Reset App State keeps the sessions unless DebugDrawer's
own settings are included, as it keeps the mocks.

### Network noise and GraphQL: ignored hosts and operation names

Analytics and image-CDN requests can bury an app's own API calls, so the log can ignore hosts. A
request's detail offers Ignore and its host, or for a host with parent domains a menu of each
(`cdn.img.example.com`, `img.example.com`, `example.com`); the Ignored hosts section, at the
bottom, lists them with Remove and takes one typed (a host, `host:port`, an IP address or a URL,
of which the host is kept; a `*` is refused, as a domain already covers its subdomains). A domain
hides its own requests and its subdomains', matched on whole labels and ignoring case, so
`example.com` hides `cdn.example.com` but not `badexample.com`; an IP address hides only itself.
Ignored requests and WebSocket connections are only left out of the list, in Captured, Previous and
Imported alike: they are still captured, written to the session and put in the bug report, and a
note under the log says how many are hidden ("12 hidden by ignore list") with Show, which lists
them until Hide. Export Shown exports what the list shows. The list is kept in `ignored.json` beside
the mock rules and loaded by `installNetwork()`, and `installNetwork(ignoring:)` adds hosts of the
app's own choosing, such as `["analytics.example.com"]`, at each launch.

Every GraphQL request has the same path, so the log names its operation: `GetUser` on a line of
its own under the row's method and path, and Operation in the detail, and the filter text
matches it. The name is a POST's JSON
`operationName`, or else the first named `query`, `mutation` or `subscription` in its `query`,
past comments and fragments; a batch shows its first two names and how many more
(`GetUser, GetPosts +1`). A GET, as a persisted query sends, is named by its `operationName`
parameter. An anonymous operation, a body that isn't JSON and one over 1 MB show no name. There is
nothing to install beyond `installNetwork()`.

### Location: a fixed coordinate or a route, without leaving your desk

`installLocation()` swaps `CLLocationManager`'s location methods, so call it at startup, before
the app starts location updates. With Spoof Location on and a coordinate typed, picked from the
presets or played from a GPX route, a manager that calls `startUpdatingLocation` gets that
location instead of real updates, then each new coordinate or route point as it changes;
`requestLocation` and `location` answer with it too. A manager already updating when spoofing
begins stops getting real updates, and turning spoofing off starts them again. The switch and the
coordinate are kept across launches, so spoofing is in effect from the next launch's
`installLocation()`. A coordinate out of range (latitude beyond ±90, longitude beyond ±180) isn't
applied.

Only `CLLocationManager`'s location updates are spoofed. These still report the real location,
which on the iOS simulator is the one Xcode or `xcrun simctl location` sets:

- `CLLocationUpdate.liveUpdates()` and `CLMonitor`: no public API reaches what they yield.
- MapKit's user location (`showsUserLocation`, `UserAnnotation`, `MapUserLocationButton`).
- Region monitoring, significant-change and visit updates, and heading.

Authorization isn't simulated: `authorizationStatus` is the real one, and a spoofed location is
delivered whether or not the app is authorized.

The plugin is debug-only: a release build swaps nothing. To spoof the location a production build
reads, for a sidecar's session, see "Location spoofing in production" below.

### Tweaks: the app's own debug settings

The Tweaks plugin shows the settings the app declares: toggles, pickers over an enumeration or a
list of strings, text fields, steppers and actions, in sections. Declare each tweak once, list
it in a section, and read it anywhere through `value`, typed as declared:

```swift
import DebugDrawerTweaksPlugin

enum Backend: String, CaseIterable {
    case production, staging, local
}

enum AppTweaks {
    static let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
    static let backend = Tweak.picker("Backend", key: "backend", default: Backend.production)
    static let greeting = Tweak.text("Greeting", key: "greeting", default: "Welcome")
    static let timeout = Tweak.stepper("Timeout (s)", key: "timeout", default: 30, in: 5 ... 120, step: 5)
}

DebugDrawer.shared.installTweaks {
    TweakSection("Features") {
        AppTweaks.newCheckout
        AppTweaks.greeting
    }
    TweakSection("Server") {
        AppTweaks.backend
        AppTweaks.timeout
    }
    TweakSection("Session") {
        TweakAction("Reset onboarding") {
            UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
        }
    }
}

// Anywhere in the app, in every build:
let url = switch AppTweaks.backend.value {
case .production: "https://api.example.com"
case .staging: "https://staging.example.com"
case .local: "http://localhost:8080"
}
```

Values persist across launches in the standard `UserDefaults`, each key behind the prefix
`com.debugdrawer.tweaks.`; pass `installTweaks(storage:)` a `UserDefaultsTweakStorage` with other
defaults or another prefix, or a `TweakStorage` of your own, to keep them elsewhere. A changed
tweak has a button that resets it, and Reset All resets them all. A stored value that is no longer
one of a tweak's values (a removed case, a number outside a stepper's range) reads as the default,
or the nearest bound. The drawer's search finds each action too. To follow a tweak as it changes,
subscribe to its `publisher`, which sends the current value first:

```swift
struct CheckoutButton: View {
    @State private var isNewCheckout = AppTweaks.newCheckout.value

    var body: some View {
        Button(isNewCheckout ? "Check out (new)" : "Check out") {}
            .onReceive(AppTweaks.newCheckout.publisher) { isNewCheckout = $0 }
    }
}
```

`Tweak`, `TweakSection` and `TweakAction` exist in every configuration. In release there is no
drawer: `value` is the declared default and `publisher` sends only that. Mark a tweak
`.productionSafe()` to let a sidecar app change it in a release build through the receiver's
tweaks capability ("Production builds: the receiver" below); the drawer shows it the same either
way. `Tweak`, its storage and its accessors live in `DebugDrawerTweaks`, a UI-free module that
`DebugDrawerTweaksPlugin` re-exports and a release build links on its own.

### Feature Flags: overriding the app's flags

The Feature Flags plugin shows every flag the app's flag service serves, with its live value, and
overrides any of them on this device. It knows no vendor: the app adapts its service (LaunchDarkly,
Firebase Remote Config, Statsig or its own) to `FeatureFlagProvider`, which lists the flags, says
what the app reads for one, and applies and clears an override. A flag's value is a Boolean, a
number or a string:

```swift
import DebugDrawerFeatureFlagsPlugin

/// The app's own flag service, adapted for the drawer: live values from the server, and overrides
/// that win over them.
final class AppFlags: FeatureFlagProvider {
    var live: [String: FeatureFlagValue] = ["new-checkout": .bool(false), "discount": .number(0.1)]
    private var overrides: [String: FeatureFlagValue] = [:]

    func flags() -> [FeatureFlag] {
        live.sorted { $0.key < $1.key }.map { FeatureFlag(key: $0.key, liveValue: $0.value) }
    }

    func currentValue(forKey key: String) -> FeatureFlagValue? {
        overrides[key] ?? live[key]
    }

    func setOverride(_ value: FeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

let appFlags = AppFlags()

DebugDrawer.shared.installFeatureFlags(provider: appFlags)

// Anywhere in the app, through the adapter, so overrides apply:
let isNewCheckout = appFlags.currentValue(forKey: "new-checkout") == .bool(true)
```

An adapter over a vendor SDK maps the SDK's flags to `FeatureFlag`s and answers
`currentValue(forKey:)` with the override it holds, if any, before asking the SDK; where the SDK has
local overrides of its own, `setOverride` and `clearOverride` call them. The plugin keeps the
overrides: they persist across launches in the standard `UserDefaults`, under
`com.debugdrawer.featureFlags.overrides`, and `installFeatureFlags` applies each one to the adapter
again before it returns, so an adapter can hold overrides in memory. Pass
`installFeatureFlags(provider:storage:)` a `UserDefaultsFeatureFlagOverrideStorage` with other
defaults or another key, or a `FeatureFlagOverrideStorage` of your own, to keep them elsewhere.

The drawer lists the flags with a search over their keys and titles and an Overridden only switch.
A Boolean flag has a switch, a number or string flag a field; an overridden flag has a button that
clears its override, and Reset All clears them all. The drawer reads the adapter again each time
it shows the plugin and when Refresh is pressed. `FeatureFlagProvider`, `FeatureFlag`,
`FeatureFlagValue` and the storage types exist in every configuration, so an adapter compiles in
release, where nothing calls it and the app reads its service's live values.

### Crash Reports: the last crash, on the next launch

After a crash on a test device there is nothing on screen to say why. Crash Reports records each
crash as it happens and shows it the next time the app starts:

```swift
import DebugDrawerCrashReportsPlugin

// At startup, after any crash SDK has installed its own handlers:
CrashReports.install()
```

`CrashReports` exists in every configuration, so the call needs no `#if DEBUG`: in release it
installs nothing. In debug builds it catches uncaught Objective-C exceptions (with
`NSSetUncaughtExceptionHandler`) and the fatal signals `SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGILL`,
`SIGFPE` and `SIGTRAP`, which is how Swift's runtime failures (a force unwrap of `nil`, an index
out of range, `fatalError`) arrive on arm64. Each handler writes a short report (what crashed,
when, the app's version and the stack: the exception's call stack symbols, or the crashed thread's
frames named by `backtrace_symbols_fd` for a signal) and then
calls the handler that was installed before it, so a crash SDK the app also uses still records
the crash; install after the SDK for that. The signal handler runs on an alternate stack, the
plugin's own unless the installing thread already has one, so a stack overflow on that thread is
recorded too. The `MXCrashDiagnostic`s MetricKit delivers, often a day later, are kept as reports
as well.

On the next launch the plugin keeps the report with the others (the newest ten, in the app's
Application Support directory; `install(directory:)` takes another), puts a badge on its header for
each report not yet opened and posts a toast for the crash it recorded itself. The drawer lists them
newest first; opening one shows its stack trace, selectable, with a button that copies the whole
report, and marks it seen. Mark All Seen clears the badge, and each report can be deleted, or all of
them. A bug report carries every report as a text file.

On macOS, AppKit catches an exception raised on the main thread while it handles an event, logs
it and carries on, so no uncaught exception reaches the handler; set the
`NSApplicationCrashOnExceptions` default to `true` to have the app crash, and be recorded, instead.

A release build installs no handlers. To get a production app's crashes, such as a dogfooder's,
let the receiver forward MetricKit's crash diagnostics to a sidecar: see "Crash reports and
MetricKit payloads in production" under "Production builds: the receiver".

### Hangs: the main thread, stuck

A hang is the main thread going too long without turning its run loop, so the app can't draw or
take a tap. The Hangs plugin catches each one as it happens, with the stack the thread was stuck
on:

```swift
import DebugDrawerHangDetectorPlugin

// At startup; a stall of the main thread over 250 ms is a hang.
HangDetector.install()

// Or with a threshold of the app's own, which the drawer can change later.
HangDetector.install(threshold: .milliseconds(100))
```

`HangDetector` exists in every configuration, so the call needs no `#if DEBUG`: in release it
starts nothing. In debug builds it adds an observer to the main run loop, which notes the time
at each turn, and starts a watcher thread that wakes four times per threshold. When the main
thread has been busy since its last turn for longer than the threshold, the watcher suspends it,
reads its registers, walks its frame records into a buffer allocated in advance and resumes it,
once per hang. When the main thread turns its run loop again, the plugin names the frames with
`dladdr`, lists the hang with how long it lasted, raises the plugin's badge and posts a toast
("Main thread hung for 612 ms"). A hang that ends before the watcher's next wake is listed
without a stack. The launch, before the main run loop first waits, isn't counted, and neither is
time the whole process spent stopped, at a debugger's breakpoint or suspended in the background.
Nor is a stall while the app is out of sight: on iOS from resigning active until it is active
again, so the deactivation, the background, the app switcher's snapshot and the return aren't
hangs, and a stall that the app resigns active in is dropped whole; a stall in the app's own code
once it is active again is counted, from becoming active. On the Mac an inactive app is still on
screen, so only a hidden one (and a Mac Catalyst app in the background) isn't counted.
The `MXHangDiagnostic`s MetricKit delivers, which describe earlier runs, are listed as well,
with a badge but no toast.

With no hang, the cost is a clock read and an uncontended lock on each turn of the main run loop,
and a watcher wake four times per threshold that does the same; `PerformanceTracesOverheadTests`
measures both. The monitor lives in `DebugDrawerHangDetector`, which the plugin re-exports, so a
production build can record hangs for a sidecar too (below, "Hangs and signposts in production"). The drawer lists the hangs newest first (the newest fifty); opening one shows its stack,
selectable, with a button that copies it, and marks it seen. Its Threshold picker changes the
threshold while the app runs, for this run only. Mark All Seen clears the badge, Clear All forgets
them, and a bug report carries them all in `hangs.txt`.

### Leaks: screens and objects that outlive their use

A retain cycle that keeps a dismissed screen alive shows nothing until memory runs short. The
Leaks plugin flags the app's view controllers still alive after their screen was dismissed, and
objects that opt in, alive in greater numbers than their class allows:

```swift
import DebugDrawerLeakDetectorPlugin

// At startup: watches the app's view controllers.
LeakDetector.install()

// An object that opts in, with one call: one should be alive at a time.
final class ProfileModel {
    init() {
        LeakDetector.trackLifetime(of: self)
    }
}
```

`LeakDetector` exists in every configuration, so the calls need no `#if DEBUG`: in release they do
nothing. In debug builds `install()` exchanges `viewDidDisappear` on `UIViewController`
(`NSViewController` on macOS) for an implementation that calls the original, then notes a view
controller that is leaving for good: on iOS, one being dismissed or removed from its container, or
inside a container that is; on macOS, any whose view leaves its window. At the end of the next turn
of the main run loop, after the autorelease pool of the turn that dismissed it has drained, one
still alive and still off screen (neither it nor its outermost container in a window or
presented) is a suspect. Every decision follows an event: the disappearance, the run loop about to
wait, a deallocation; nothing waits on a timer. The detector holds no reference: an object of its
own, attached to each one it watches, tells it of the deallocation. Only the app's own classes are
watched, not the system's (SwiftUI's hosting and presentation controllers, alerts), which their
frameworks keep for reuse; a plain `UIHostingController<Content>` is a specialization made at run
time and isn't watched either, while a subclass of it is.

`trackLifetime(of:maxCount:)` counts an object among the live instances of its class until it
deallocates; while more than `maxCount` (one by default) are alive, the class is a suspect. It can
be called from any thread, and before `install()`.

The plugin lists the suspects by class, most recently flagged first, with how many are alive, puts
a badge on its header for each and posts a toast ("ProfileViewController is still alive after it
was dismissed"). A suspect that deallocates later, or is shown again, stops being one. Ignore hides
a class for this run, Stop Ignoring brings them back, and a bug report carries the suspects in
`leaks.txt`. A screen the app keeps on purpose to show again is flagged while it is off screen;
ignore its class.

### MetricKit: the system's own measurements

MetricKit delivers the app a day's metrics (launch-time and hang histograms, disk writes, memory,
CPU, exits) about once a day, and diagnostics (crashes, hangs, CPU and disk-write exceptions,
slow launches) as they happen. The MetricKit plugin keeps every payload, so they can be read on
the device that measured them:

```swift
import DebugDrawerMetricKitPlugin

// At startup:
MetricKitPayloads.install()

// A payload from elsewhere, such as one a device exported:
let json = Data(#"{"appVersion": "1.2", "cpuMetrics": {}}"#.utf8)
MetricKitPayloads.add(json: json, kind: .metrics)
```

`MetricKitPayloads` exists in every configuration, so the calls need no `#if DEBUG`: in release
they do nothing. In debug builds `install()` subscribes to `MXMetricManager` (macOS reports
a subset of the metrics iOS does), and first keeps the payloads
the system still holds from before. MetricKit delivers to every subscriber, so an analytics SDK,
Crash Reports and Hangs subscribing as well still get each payload. `add(json:kind:)` keeps a
payload the app has from elsewhere as if MetricKit had delivered it; the period it covers is read
from its `timeStampBegin` and `timeStampEnd`. MetricKit delivers nothing in the simulator, so
the example apps add a sample pair from a button, Add Sample MetricKit Payloads.

Each payload is kept once (the same kind and JSON delivered again adds nothing), the newest fifty,
in the app's Application Support directory (`install(directory:)` takes another), so the history
survives relaunches. The drawer lists them, the latest period first, each with its kind, the
period it covers and a line of what it holds (`App 1.2 (34) · 9 metric groups`,
`1 crash · 2 hangs`), puts a badge on its header for each not yet opened and posts a toast for
each new one. Opening one shows its JSON, indented with sorted keys and selectable, with Copy JSON
and Export, which shares it as a `.json` file, and marks it seen. Mark All Seen clears the badge,
and each payload can be deleted, or all of them. A bug report carries every payload as a JSON file.

`MetricKitPayloadKind` and the subscriber live in `DebugDrawerMetricKit`, a UI-free module the
plugin re-exports, which a release build can link beside the receiver to forward payloads to a
sidecar ("Crash reports and MetricKit payloads in production", below).

### Permissions: why the camera doesn't work

The Permissions plugin lists every privacy permission the app's Info.plist declares a usage
description for, with the status the system reports for it now:

```swift
import DebugDrawerPermissionsPlugin

// At startup:
PrivacyPermissions.install()
```

`PrivacyPermissions` exists in every configuration, so the call needs no `#if DEBUG`: in release it
does nothing, and the plugin references none of the frameworks that report a status. In debug builds
each permission shows its name, its status (Allowed, While Using, Limited, Denied, Restricted, Not
Asked and so on, with a glyph for whether it grants access, partly or not), and the usage
descriptions that declare it with their keys:

| Permission | Keys | Platforms |
|---|---|---|
| Camera | `NSCameraUsageDescription` | iOS, macOS |
| Microphone | `NSMicrophoneUsageDescription` | iOS, macOS |
| Photos | `NSPhotoLibraryUsageDescription` | iOS, macOS |
| Photos (Add Only) | `NSPhotoLibraryAddUsageDescription` | iOS, macOS |
| Location | `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription`, `NSLocationUsageDescription` | iOS, macOS |
| Contacts | `NSContactsUsageDescription` | iOS, macOS |
| Calendars | `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`, `NSCalendarsUsageDescription` | iOS, macOS |
| Reminders | `NSRemindersFullAccessUsageDescription`, `NSRemindersUsageDescription` | iOS, macOS |
| Notifications | none needed | iOS, macOS |
| Tracking | `NSUserTrackingUsageDescription` | iOS, macOS |
| Motion & Fitness | `NSMotionUsageDescription` | iOS |
| Speech Recognition | `NSSpeechRecognitionUsageDescription` | iOS, macOS |
| Bluetooth | `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription` | iOS, macOS |
| Local Network | `NSLocalNetworkUsageDescription` (no status API: listed as declared) | iOS, macOS |
| Media & Apple Music | `NSAppleMusicUsageDescription` | iOS |

Notifications need no usage description, so every app may ask for them, and they are always
listed. Any other `NS…UsageDescription` key (Face ID, HealthKit) is listed too, marked as not
checked, and a key declared on a platform without the permission is marked as not on it.

A status is read again each time the app becomes active, as it does on coming back from Settings
or from a system prompt, when Location reports a change, and after a request; nothing polls.
While the user hasn't decided, Request shows the system's prompt; a request that needs a key the
Info.plist lacks (Calendars and Reminders with only the legacy key, Location without the
when-in-use key) names the key instead. Open Settings opens the app's page in Settings on iOS
(its notification settings for Notifications), and the permission's pane under Privacy & Security
in System Settings on macOS. A bug report carries `permissions.txt`: each permission, its status
and its keys.

### Notifications: the device token and a push without a server

The Notifications plugin shows the APNs device token, the app's notification settings, its pending
and delivered notifications, and sends a pasted APNs payload as a local notification, so the app's
handlers can be exercised without a push server. The app passes the token on from its delegate:

```swift
import DebugDrawerNotificationsPlugin

// At startup:
PushNotifications.install()

// In application(_:didRegisterForRemoteNotificationsWithDeviceToken:):
PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)

// In application(_:didFailToRegisterForRemoteNotificationsWithError:):
PushNotifications.didFailToRegisterForRemoteNotifications(withError: error)
```

A SwiftUI app gets those delegate methods through `@UIApplicationDelegateAdaptor` (or
`@NSApplicationDelegateAdaptor`). `PushNotifications` exists in every configuration, so the calls
need no `#if DEBUG`: in release they do nothing, and the plugin's own code touches nothing of User
Notifications (the binary still links the framework, through `DebugDrawerNotifications`, which the
plugin re-exports and whose push registration capability reads the settings in release). In debug
builds the plugin shows:

- **APNs device token**: the token as hexadecimal with Copy Token, or why registering failed. It is
  a device identifier, so it is masked under the drawer's redaction rules (the standard rules mask
  any key containing `token`) until the eye button reveals it, and in bug reports; Copy Token copies
  the token itself, for pasting into a push tool. The simulator gives a token to an app whose
  entitlements declare `aps-environment`; on the Mac that entitlement needs a provisioning profile.
- **Authorization**: the status (Allowed, Denied, Provisional, Not Asked and so on), each
  presentation setting (alerts, sounds, badges, lock screen, Notification Center, critical, time
  sensitive, alert style, previews), Request while the user hasn't decided, and Refresh.
- **Send a payload**: an editor for an APNs payload, checked as it is typed, and a delay (now, 5 or
  30 seconds, long enough to put the app in the background). `aps` gives the alert (a string, or a
  dictionary with `title`, `subtitle` and `body`), `badge`, `sound` (`default`, a file name, or a
  critical sound dictionary), `category`, `thread-id`, `target-content-id`, `interruption-level` and
  `relevance-score`; the whole payload, `aps` and every key beside it, becomes the notification's
  `userInfo`, as the app's handlers would get it from APNs. Notes say what a local notification does
  differently: localization keys show as the keys themselves, `content-available` doesn't wake the
  app in the background, `mutable-content` doesn't run a notification service extension, and a
  payload over 4 KB would be refused by APNs. Sending asks for authorization first if the user
  hasn't decided.
- **Pending** and **Delivered**, each with its count, newest first: each request and notification
  on one line, its title and the time it was delivered or fires next, removable; opening one shows
  its subtitle, body, identifier, trigger (after an interval, on a date, at a location) or delivery
  time, category, thread, badge and `userInfo`. Each list shows its newest five until Show All, and
  has Remove All.

While the app is in front, the system shows a notification only if the app's
`UNUserNotificationCenterDelegate` asks for a banner in `userNotificationCenter(_:willPresent:)`;
the plugin never takes the delegate, which stays the app's. It reads the center when installed,
each time the app becomes active, after a request or a send and on Refresh; nothing polls. To
send a real remote notification to the simulator from the Mac instead, `xcrun simctl push
<device> <bundle id> payload.json` takes the same JSON. A bug report carries `notifications.txt`:
the token (masked), the settings, and every pending and delivered notification.

`NotificationSettings` lives in `DebugDrawerNotifications`, the plugin's UI-free half, which the
plugin re-exports. A release build links that module beside the receiver to show a sidecar the
token, the push environment and the settings during its session ("Push token and environment for
test pushes", under "Production builds: the receiver").

### Background Tasks: launching a task without waiting for the system

The Background Tasks plugin lists the task identifiers the Info.plist permits
(`BGTaskSchedulerPermittedIdentifiers`) and the requests waiting in `BGTaskScheduler`, and copies
the LLDB commands that make the system launch a task, or expire it, at once:

```swift
import DebugDrawerBackgroundTasksPlugin

// At startup, after registering the app's own launch handlers:
BackgroundTaskRequests.install()
```

`BackgroundTaskRequests` exists in every configuration, so the call needs no `#if DEBUG`: in
release it does nothing, and the plugin references nothing of BackgroundTasks. macOS has no
`BGTaskScheduler`, so there it adds nothing either; on iOS, iPadOS and Mac Catalyst the plugin
shows:

- **Permitted Identifiers**: each identifier, whether a request for it is pending, a Schedule button
  for each kind the `UIBackgroundModes` allow (App Refresh for `fetch`, Processing for
  `processing`), which submits a request that may begin now, and a Copy LLDB Command menu with its
  launch and expiration commands. A refused request shows why on its row: unavailable (the
  simulator, or Background App Refresh turned off), not permitted, or too many pending. A wildcard
  identifier (`….*`, for continued processing tasks) is listed with what it is for, without these
  buttons. Without the modes the section warns that the system runs no request.
- **Pending Requests**: each request with its identifier, kind (app refresh or processing, with
  whether it needs network or external power) and earliest begin date, each cancellable, with Cancel
  All and Refresh.

The plugin registers no launch handlers: `BGTaskScheduler` requires the app's own, registered for
every permitted identifier before it finishes launching
(`BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` in
`application(_:didFinishLaunchingWithOptions:)`).

To run a task's launch handler now, on a device (the simulator runs no background tasks):

1. Schedule a request for the identifier, from the drawer or from the app's own code.
2. Copy its launch command from the Copy LLDB Command menu beside the identifier:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.refresh"]`
3. Pause the app in Xcode (Debug ▸ Pause, or the pause button in the debug bar), paste the command
   at the `(lldb)` prompt, press Return, and continue the app. The system launches the task as it
   would in the background.
4. To test the expiration handler, pause again while the task runs and paste its expiration
   command, `_simulateExpirationForTaskWithIdentifier:` with the same identifier.

The drawer only copies these commands: the selectors are private API, which the app itself never
calls. It reads the pending requests when installed, each time the app becomes active, after a
Schedule and on Refresh; nothing polls. A bug report carries `background-tasks.txt`: the
background modes, the permitted identifiers and every pending request.

### Analytics: did the right event fire?

The Analytics plugin lists the analytics events the app sends, as it sends them, so QA can check
that the right event fired with the right properties. The app records each event where it hands
it to its analytics service:

```swift
import DebugDrawerAnalyticsPlugin

// At startup:
AnalyticsEvents.install()

// Wherever the app sends an event to its analytics service:
AnalyticsEvents.record("checkout_completed", properties: [
    "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
    "items": ["sku-1", "sku-2"], "shipping": ["country": "NZ"]
], source: "Segment")

// From an SDK's untyped properties:
let properties: [String: Any] = ["screen": "Settings", "dark_mode": true]
AnalyticsEvents.record("screen_viewed", properties: properties.mapValues(AnalyticsValue.init(converting:)))
```

`AnalyticsEvents` and `AnalyticsValue` exist in every configuration, so the calls need no
`#if DEBUG`: in release they do nothing, and `record` doesn't even evaluate its arguments, unless a
sidecar's session is mirroring analytics events (below). In
debug builds `record` can be called from any thread or actor and returns at once. Property values
are `AnalyticsValue`s (strings, integers, doubles, Booleans, dates, `nil`, arrays and objects of
them), which literals convert to; `AnalyticsValue(converting:)` reads a value from a
`[String: Any]` as SDKs take them. `source` names the service, for an app that sends to more than
one.

The plugin keeps the newest thousand events in memory (`install(capacity:)` takes another number),
including those recorded before `install()`, so the ones sent while the app launches show too.
The drawer lists them, the newest first, each with its name, the time it was recorded to the
millisecond, its source and how many properties it has; the header shows how many there are, and
a badge counts those that arrived while the list was off screen. The filter matches the name, the
source, and property keys and values, nested ones included. Opening an event shows each property
beside its key and the event's JSON (sorted keys, ISO 8601 dates), with Copy JSON. Export All
shares every event as a `.json` array, and Clear drops them. Values the redaction rules call
sensitive (an `auth_token`, say) are masked on screen until revealed, and in the copy, the export
and the bug report, which carries every event as `analytics.json`. The plugin runs on every
platform the drawer does; tvOS and watchOS have no pasteboard or share sheet, so there it offers
no Copy JSON or Export All.

`AnalyticsEvents`, `AnalyticsValue` and the sink live in `DebugDrawerAnalytics`, a UI-free module
that `DebugDrawerAnalyticsPlugin` re-exports and a release build links on its own. Through it, a
release build's receiver can mirror the events recorded during a sidecar's session, redacted in the
app ("Production builds: the receiver" below); in debug builds the drawer keeps them as well.

### Databases: what the app actually saved

The Databases plugin finds the app's SQLite, Core Data and SwiftData stores and opens them read-only,
so a developer can check what the app wrote without copying the file off the device:

```swift
import DebugDrawerDatabaseBrowserPlugin

// At startup:
DatabaseBrowser.install()

// Or with folders of the app's own as well:
DatabaseBrowser.install(additionalDirectories: [URL.cachesDirectory.appending(path: "Databases")])
```

`DatabaseBrowser` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`. The plugin looks in Application Support, Documents and the containers of the app groups
the app's entitlements name (and in `additionalDirectories`), for `.sqlite`, `.sqlite3`, `.db` and
`.store` files that begin with SQLite's header or are empty; `-wal`, `-shm` and `-journal` files
belong to their store and aren't listed apart. A Mac app outside the sandbox has only its own folder
of Application Support searched, and no Documents. Each store shows its path, size, journal mode and
kind; a Core Data or SwiftData store (one with `Z_METADATA` and `Z_PRIMARYKEY`) lists its tables by
entity name, with the `Z` table beneath, and its model's version hash. Opening a table pages its
rows fifty at a time in a grid that scrolls sideways, with a search over its text columns; NULLs,
numbers, text and blobs (size and first bytes) are each drawn their own way, and tapping a cell
shows its whole value. The query editor runs one `SELECT` (or a pragma that describes a table),
reading up to 200 rows; the page and the result copy as CSV.

The browser only reads. It opens a store with `SQLITE_OPEN_READONLY`, sets `query_only`, and an
authorizer refuses anything but reading, so `INSERT`, `UPDATE`, `DELETE`, `ATTACH`, pragmas that
change the store and a second statement show as inline errors. A connection is open only while a
read runs, so the app's own writes and checkpoints are never held up for long, and a store the app
holds locked shows "Store busy, try again". Reading a WAL store needs to write its `-shm` file; the
browser says when it can't. The bug report carries `databases.txt`: each store with its tables and
row counts, never their rows. tvOS and watchOS have no pasteboard, so there it offers no copy.

### UserDefaults: app group suites, and values of every type

The UserDefaults plugin lists the keys of the standard defaults and of any suite the app names,
such as an app group's it shares with its extensions:

```swift
import DebugDrawerUserDefaultsPlugin

// At startup:
UserDefaultsBrowser.install(suites: ["group.com.example.shared"])
```

`UserDefaultsBrowser` exists in every configuration and does nothing in release, so the call needs
no `#if DEBUG`. With suites named, a picker above the list switches between Standard and each suite.
The list holds the keys the app wrote. Selecting one edits its value whatever its type: a string,
number or data in a field (data in hex or Base64, as toggled), a Boolean as true or false, a date
with a date picker, and an array or a dictionary as a list of what it holds, where tapping an item
drills in, however deep. Text that isn't a value of the type says why under the field, and Save
waits until it is. Each edit writes the key's whole value back. Add Key adds a key of a chosen type,
starting empty (a date starts now), and an array or a dictionary takes items the same way. The list
follows the app's writes to any suite in the process as they happen
(`UserDefaults.didChangeNotification`); a write from another process, such as an extension's, shows
after Reload, in the menu beside Add Key. Show Other Domains, in the same menu, adds the registered,
launch-argument and global keys, each marked with where it comes from and read-only. The bug report
carries the standard defaults' keys as `user-defaults.json`.

### Disk I/O: what the app reads and writes, and on which thread

`DebugDrawer.shared.installDiskIO()` records the app's file calls as they happen: each call's
operation, path, bytes, duration and thread, and the error of one that failed. Calls on the main
thread carry a warning, and the totals (reads, writes, the bytes of each, main-thread calls and
failures) count every call since Clear, not only the 500 the list keeps. Calls reach the drawer in
batches, one per turn of the main queue, however many the app makes. Pause drops the calls made
until Resume, neither listing nor counting them. The Disk section shows how
full the home volume is and its free space, read when the plugin appears and on Refresh. The list
keeps the newest 500 calls; set `DiskIOStore.shared.capacity` for another number.

What is recorded, through swizzled methods the install alone puts in place:

- `FileManager`: `contents(atPath:)`, `createFile(atPath:contents:attributes:)`, `createDirectory`,
  `removeItem`, `contentsOfDirectory`, `copyItem` and `moveItem` (each by path and by URL), and
  `attributesOfItem(atPath:)`;
- `NSData`: `write(toFile:)` and `write(to:)` (with `atomically:` or `options:`), and its
  `contentsOfFile:` and `contentsOf:` initializers;
- `FileHandle`: the Objective-C reads and writes on regular files: `readData(ofLength:)`,
  `readDataToEndOfFile()`, `availableData`, `read(upToCount:)`, `readToEnd()` and `write(_:)`.

What `installDiskIO()` doesn't record, on current OSes, as none of it reaches a method the plugin
can swizzle (the unsafe install below records the first four): Swift's `Data.write(to:)`,
`Data(contentsOf:)` and `FileHandle.write(contentsOf:)`, `String`'s file methods, POSIX calls (`open`, `read`, `write`), SQLite, Core Data and `UserDefaults`. Nor is a
`FileHandle` call that fails, a call that Foundation makes inside a recorded one, or the drawer's
own file work: the File Browser's listings, bug reports, and the plugins' saved settings and
sessions. A plugin of your own marks its file work the same way, so it stays out of the list:

```swift
let names = try DebugDrawerActivity.$isDrawerWork.withValue(true) {
    try FileManager.default.contentsOfDirectory(atPath: folder)
}
```

#### Recording Swift's Data and FileHandle calls: an unsafe install

`DebugDrawer.shared.unsafeInstallDiskIOWithInterposing()` does what `installDiskIO()` does, and
also records Swift's `Data.write(to:)`, `Data(contentsOf:)` and `FileHandle.write(contentsOf:)`,
and `String`'s file methods: each `read`, `write`, `pread` and `pwrite` on a regular file that no
swizzled method records, with its path, bytes, duration, thread and error. A read that reaches
the end of a file, or a write of no bytes, moves nothing and isn't listed; a call to a pipe, a
socket or a terminal isn't the disk and isn't either. The drawer's own work stays out, as it does
for the swizzled calls.

It needs the app to link one more product, the `DebugDrawerDiskIOInterposer` dynamic library,
which holds dyld interposing tuples for those four functions:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "DebugDrawerDiskIOPlugin", package: "DebugDrawer"),
    .product(name: "DebugDrawerDiskIOInterposer", package: "DebugDrawer"),
])
```

In Xcode, add `DebugDrawerDiskIOInterposer` to the app target's Frameworks, Libraries, and
Embedded Content, embedded. The plugin never links it: the install looks it up at runtime, so an
app that doesn't link it, or a build where dyld didn't load it at launch (a library opened with
`dlopen`, a plugin bundle, a test bundle SwiftPM loads), records what `installDiskIO()` records
and logs why. Before iOS 18 Foundation's Swift calls reach the `NSData` and `FileHandle` methods
the plugin swizzles, so there the install leaves interposing off. The library's functions pass
every call straight to the system until the install turns them on, and a release build's library
holds nothing.

What makes it unsafe: dyld interposing is undocumented behaviour, which a new OS can change or
drop without notice; an App Store build may be rejected for linking a library that uses it, so
link it into debug builds only (a separate debug target, or a scheme that leaves it out of
release); and once on, the plugin's code runs inside every `read` and `write` the process makes,
on every thread, so a crash or a deadlock there takes the app with it. dyld applies interposing
only to a process it trusts: a debug build signed for development is one, a hardened one may not
be.

### File Browser: what the app wrote to disk

The File Browser plugin lists the app's own folders, so a developer can see what it wrote, how big
it is, and what is inside, without copying the container off the device:

```swift
import DebugDrawerFileBrowserPlugin

// At startup:
FileBrowser.install()

// Or with the containers of the app's groups as well:
FileBrowser.install(appGroups: ["group.com.example.orders"])
```

`FileBrowser` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`. Its roots are Documents, Library, tmp, the app bundle and the shared container of each
group in `appGroups` (from `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`); a
group the system gives no container is listed as missing. A Mac app outside the sandbox shares
those folders with the user's other apps, so there it lists its own folders of Application Support
and Caches instead of Documents and Library. Every folder shows the total size of what it holds,
at any depth, counted off the main thread and stopped when you leave it; folders and files show
their size and their modified and created dates.

A file opens to a preview, told from its bytes rather than its name: text, JSON pretty-printed with
its keys sorted, property lists (binary or XML) as XML, and images as a thumbnail with their pixel
size. The first megabyte of text is read, and longer text says it is cut short; an image is read
whole, up to 64 MB. A SQLite file is listed
like any other, with no preview. A file can be shared, its path or text copied, and on the Mac
revealed in Finder. Import… copies a picked file into the folder shown, and Rename… and Delete
(which asks first) change a file or folder, anywhere but in the bundle, which is read-only.

### Localization: text that doesn't fit, and strings nobody translated

The Localization plugin pseudo-localizes the app's strings or shows their keys, while the app runs,
and lists the translations a language is missing:

```swift
import DebugDrawerLocalizationPlugin

// At startup, before the first string is looked up:
Localization.install()

// Or, for a launch argument of the app's own, starting pseudo-localized:
Localization.install(mode: ProcessInfo.processInfo.arguments.contains("-PseudoLocalize") ? .pseudoLocalized : .standard)
```

`Localization` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`. In debug builds `install()` replaces `Bundle`'s public lookup,
`localizedString(forKey:value:table:)`, which `NSLocalizedString` calls. Pseudo-Localize turns
"Settings" into "[Šéţţîñĝš····]": every letter accented, about 40% longer, and bracketed, so
clipped or concatenated text shows. Format specifiers (`%@`, `%1$lld`, `%.2f`) are kept, and a
plural from a `.stringsdict` keeps its rules: each variant is rewritten and looked up again, so
"1 order" and "3 orders" still differ. Show Keys draws each string's key in its place. Both apply
only to the app's own bundles (the main bundle and the bundles and frameworks inside it), never to
the drawer's or the system's, and only to strings the app's tables hold or that pass a default
value; SwiftUI's own strings that it resolves against the main bundle are left alone.

SwiftUI's `Text("key")`, `String(localized:)` and `LocalizedStringResource` don't go through that
lookup, so the live modes don't reach them. For those, Whole App on Next Launch stores Foundation's
own settings in the app's defaults: Accented and Doubled sets `NSAccentuateLocalizedStrings` and
`NSDoubleLocalizedStrings`, Untranslated in Capitals sets `NSShowNonLocalizedStrings`, and turning
one off removes its keys. Foundation reads them at launch, so they take effect when the app is next
launched, and they change every string, the drawer's and the system's included. Until then the
plugin shows "Relaunch to apply", and its header says "relaunch to apply" or, while the app runs
with them, "whole app", so an app that comes up accented says why. The plugin also lists Apple's
launch arguments, to copy into the scheme: `-NSDoubleLocalizedStrings YES`,
`-NSAccentuateLocalizedStrings YES`, `-NSShowNonLocalizedStrings YES`,
`-NSForceRightToLeftWritingDirection YES` and `-AppleLanguages` with the language picked under
Missing Translations (`-AppleLanguages (de)`). Show Keys has no Foundation
setting, so it is live only. Foundation's accenting marks the letters of format specifiers too, so
a string formatted from an accented format can lose its arguments (`Delivery: @`); the live mode
keeps them.

Text already on screen is redrawn when the mode changes under `.debugLocalization()`, which gives
the views below it a new identity (and so resets their `@State`); text elsewhere changes the next
time it is looked up.

Missing Translations compares each language's `.strings` and `.stringsdict` tables in the app's
`.lproj` folders with the development language's (and `Base.lproj`), by table, and adds the keys the
app looked up while running and got no translation for, marked "Looked up". The list has a language
picker and a filter, copies as text or CSV, and the plugin's header shows how many are missing for
the current language. The bug report carries `localization.txt`: the mode, the languages and what
each is missing. tvOS and watchOS have no pasteboard, so there it offers no copy.

The live modes replace `Bundle`'s lookup, which a release build never does. There a sidecar
switches the strings the app reads through `LocalizationReview` to their keys or pseudo text
instead ("Localization review in production", below).

### Screen Recording: a video of the bug, without the drawer in it

The Screen Recording plugin records the app as a QuickTime movie, started and stopped
from the drawer or from the HUD, and leaves the drawer, its HUD and its toasts out of the movie:

```swift
import DebugDrawerScreenRecordingPlugin

// At startup:
ScreenRecording.install()

// Or keep the newest ten recordings rather than five:
ScreenRecording.install(capacity: 10)
```

`ScreenRecording` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`, and a release build links no AVFoundation through it. The plugin draws the app's own
windows into each frame, up to 30 a second, rather than recording the screen, so it asks for no
permission: on iOS every window of the scene in front, sheets and alerts included, and on macOS the
content of the main window. The drawer is open while it records without appearing in the movie: its
windows, the HUD's and the toasts' among them, are left out. Pin it to the HUD (Show in HUD)
to start and stop it with the drawer closed. On iOS and Mac Catalyst, Show touches draws a circle
where each finger is, in the movie only; it is off until turned on, and remembered.

Movies are H.264, at the window's size up to 1920 pixels on the longer side, and are saved in
`Caches/DebugDrawer/Recordings` (in a Mac app outside the App Sandbox,
`Caches/<bundle identifier>/DebugDrawer/Recordings`), the newest five (or `capacity`) kept. Each is listed with when it
started, its length and size, and can be shared or deleted. The newest is marked In Bug Report and
goes into the bug report's Screen Recording folder; any other can be added. The movie shows what the
app's layers hold when each frame is drawn, so an animation Core Animation runs on its own shows at
its end, and Metal, video and web content may draw blank.

### Design Overlay: the screen against the mockup

The Design Overlay plugin lays a design comp over the running app, to catch pixel drift: at an
opacity, an offset and a scale, normal or in a difference blend.

```swift
import DebugDrawerDesignOverlayPlugin

struct ShopApp: App {
    init() {
        // At startup:
        DesignOverlay.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .debugDesignOverlay() // beneath .debugDrawer(), so the mockup lies under the drawer
                .debugDrawer()
        }
    }
}
```

`DesignOverlay` and `.debugDesignOverlay()` exist in every configuration and do nothing in
release, so neither needs `#if DEBUG`. The mockup is picked in the drawer: from Photos or Files on
iOS and Mac Catalyst, from a file or the pasteboard (an image, or an image file copied in the
Finder) on macOS. Photos runs out of the app's process, so nothing asks for a permission. The
mockup is kept in `Caches/DebugDrawer/DesignOverlay` (in a Mac app outside the App Sandbox,
`Caches/<bundle identifier>/DebugDrawer/DesignOverlay`) with its settings, so it is there again on the
next launch, until Clear. `DesignOverlay.install(mockup:)` takes an image's data instead, for a
comp the app bundles or generates, shown for that launch without replacing the saved one.

The mockup is drawn from the window's top-leading corner, under the safe area as a screen's mockup
is: Automatic infers whether it was exported at @1x, @2x or @3x from its width against the window's,
and Fit Width, @1x, @2x and @3x set it. Opacity runs from 5% to 100%, and Difference draws black
where the app matches the mockup and bright where it drifts. The X and Y steppers move it a point at
a time; with Move by Dragging on, a drag anywhere in the window moves it, and a bar at the bottom
leading corner shows the offset and Done. Outside Move the mockup takes no touches or clicks, so the
app under it keeps working. The plugin's header shows the opacity and blend, "Hidden" or "Moving",
and its HUD readout (Show in HUD) hides and shows the mockup with the drawer closed, or ends Move.
The mockup belongs to the app's content, so screenshots and screen recordings include it.

### Color Vision: meaning carried by color alone

The Color Vision plugin simulates protanopia, deuteranopia, tritanopia and grayscale over the app's
views while it runs, so a designer can see what carries meaning by color alone: an error that reads
like a success, chart series that merge.

```swift
import DebugDrawerColorVisionPlugin

struct ShopApp: App {
    init() {
        // At startup:
        ColorVision.install()
    }

    var body: some Scene {
        WindowGroup {
            OrdersView(orders: Order.samples)
        }
    }
}

// A screen's content, inside its ScrollView:
struct OrdersView: View {
    let orders: [Order]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Orders")
                    .font(.title)
                ForEach(orders) { order in
                    DeliveryBadge(isLate: order.isLate)
                }
            }
            .debugColorVision()
        }
    }
}

// In a List, each row's content:
struct OrderHistory: View {
    let orders: [Order]

    var body: some View {
        List(orders) { order in
            DeliveryBadge(isLate: order.isLate)
                .debugColorVision()
        }
    }
}

// A view whose colors carry meaning:
struct DeliveryBadge: View {
    let isLate: Bool

    var body: some View {
        Label(isLate ? "Late" : "On time", systemImage: "clock")
            .foregroundStyle(isLate ? .red : .green)
    }
}
```

`ColorVision` and `.debugColorVision()` exist in every configuration and do nothing in release, so
neither needs `#if DEBUG`. The simulation is picked in the drawer, from Off, Protanopia,
Deuteranopia, Tritanopia and Grayscale, and applies live to every view under `.debugColorVision()`,
while the drawer, its HUD and its toasts keep their colors. The plugin's header names the simulation
on, and its HUD readout (Show in HUD) moves to the next one with each tap, so they can be compared
with the drawer closed. Each launch starts with the app's own colors; `install(simulating:)` starts
in a simulation instead, for a launch argument of the app's own.

Each pixel is decoded to linear RGB, multiplied by the simulation's matrix and encoded again: Machado,
Oliveira and Fernandes's matrices (2009) at full severity for the three dichromacies, and Rec. 709
relative luminance for grayscale. The matrix runs as a Metal shader through SwiftUI's `colorEffect`,
which draws what SwiftUI draws. A view that UIKit or AppKit backs (`List`, `Form` and
`NavigationStack` on iOS, `ScrollView` on macOS, text fields, maps, web views) shows SwiftUI's
placeholder under it while a simulation is on, so apply the modifier to a screen's content: inside
its `ScrollView`, or to each `List` row's content, rather than to the app's root. Leave controls
UIKit or AppKit draws outside it, such as text fields, steppers, sliders and toggles. For the
whole screen, every view included, the system's own color filters do it: Settings › Accessibility ›
Display & Text Size › Color Filters on iOS, and System Settings › Accessibility › Display › Color
filters on macOS. The plugin's footer names them; it never turns them on. With no simulation
on, the modifier adds nothing, and the view draws exactly as without it; turning a simulation on or
off draws the view anew, so the `@State` inside it starts over. The plugin builds for macOS, iOS,
Mac Catalyst, visionOS and tvOS; SwiftUI has no shaders on watchOS.

### Reset App State: a fresh install without reinstalling

The Reset App State plugin clears what deleting the app and installing it again would, without
doing either: a checkbox for each kind of state, what it will delete beside it, a confirmation that
lists it, and an optional restart.

```swift
import DebugDrawerAppStateResetPlugin

// At startup:
AppStateReset.install()

// Or with the app's other stores, and a cleanup of its own:
AppStateReset.install(
    appGroups: ["group.com.example.orders"],
    directories: [URL.libraryDirectory.appending(path: "Exports")],
    cleanup: AppStateReset.Cleanup("Close the orders database") {
        OrdersDatabase.shared.close()
    }
)
```

`AppStateReset` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`, and a release build links no WebKit through it. The categories, each cleared on its own:

| Category | What it deletes |
|---|---|
| UserDefaults | The keys of the app's domain and of each app group's suite, listed by name |
| Keychain | Every generic and internet password, certificate, key and identity the app can read, each by its persistent reference, listed by service and account or by label |
| Files | The contents of Documents, Application Support and tmp, each app group's container less its Library/Preferences and Library/Caches, and the `directories` given; never the directories themselves |
| Caches | The contents of Library/Caches, the app's and each app group's |
| Cookies | `HTTPCookieStorage.shared`'s cookies, and `WKWebsiteDataStore.default()`'s where WebKit exists, listed by domain |
| URL cache | `URLCache.shared`'s responses, its disk and memory use shown |
| App cleanup | The `cleanup` the app gave, run first, so it can close a database before its file goes |

Every category is read when the plugin is first shown, and again on Refresh, before anything is
deleted. Reset… opens the confirmation, which lists exactly what will go: each key, keychain item,
top-level file or folder with its size, and cookie domain. Reset deletes that and nothing else;
Reset and Relaunch then starts a new instance of the app on macOS and quits this one. An iOS,
tvOS, visionOS or Mac Catalyst app can't launch itself, so there the button is Reset and Quit, and
the app is opened again from the Home Screen (the Home View on visionOS, the Dock or the Finder in
Mac Catalyst). UserDefaults are written to disk and WebKit's cookie
store waited on before the app ends. When something can't be deleted (a file in a folder that can't
be written, an item the keychain refuses), the app keeps running and the results name it and why.

Links are deleted as links, never followed out of the container. App groups the entitlements name
are found on their own. DebugDrawer's own state stays unless Include DebugDrawer's own settings is
on: the drawer's own defaults suite (`<bundle identifier>.debugdrawer`: its layout, HUD pins and
plugin settings), the keys starting `com.debugdrawer.` in the app's domain (Tweaks' values and
Feature Flags' overrides) and the files named `DebugDrawer…` in each directory and in its folder named after the
app (recordings and mockups in `Caches/DebugDrawer`, or `Caches/<bundle identifier>/DebugDrawer` in a
Mac app outside the App Sandbox, crash reports and MetricKit payloads).

On iOS, tvOS and visionOS each app has a keychain of its own, and a query sees only the access
groups its entitlements name. On the Mac and in Mac Catalyst the plugin asks the data protection
keychain, which is scoped the same way, never the login keychain, whose items belong to every app
the user runs; an app without a keychain entitlement there gets `errSecMissingEntitlement`, which
the plugin shows, and nothing is deleted. So does a simulator build whose entitlements lack
`application-identifier`, which Xcode adds and Bazel's rules_apple doesn't. A Mac app that isn't
sandboxed shares Documents, Application Support, Caches and the temporary directory with every other
app, so there Files clears only Application Support's folder named after the app, and Caches only
Caches' one. The plugin builds for macOS, iOS, Mac Catalyst, visionOS and tvOS. A production build
resets the same categories from a sidecar: see Resetting the app's state, under Production builds.

### View Inspector: which views keep re-rendering

The View Inspector plugin counts how many times a view's body is evaluated, for the views the app
names with `.trackRenders(_:)`. Apply it to the outermost view of the body to count, since it
counts each time the body that applies it runs:

```swift
import DebugDrawerViewInspectorPlugin

struct OrderRow: View {
    let title: String
    let total: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(total)
        }
        .trackRenders("OrderRow")
    }
}
```

Its SwiftUI Renders section lists each name with its count, busiest first, and Reset starts them
over. A row that renders again when nothing it shows has changed is reading state it doesn't need.
Flash Renders outlines a tracked view each time its body runs, unless Reduce Motion is on. The
drawer tracks none of its own views, so only the app's appear. In release builds
`.trackRenders(_:)` returns the view unchanged.

### Remote viewing: a phone's logs and requests on a Mac

`DebugDrawerRemote` serves the Network and Console plugins' models, or any plugin's, to a viewer
on another device over the local network, so a phone's traffic can be read on a Mac's screen.
Nothing listens or advertises until the app starts the server, and a viewer reaches nothing until
it pairs with a code the device shows.

On the device, register the models to offer and start the server, in a debug build:

```swift
import DebugDrawer
import DebugDrawerConsolePlugin
import DebugDrawerNetworkPlugin
import DebugDrawerRemote
import SwiftUI

@MainActor
final class RemoteViewing {
    let registry = DebugDrawerModelRegistry()
    let server: DebugDrawerNetworkServer

    init() {
        registry.register(NetworkModel.shared, id: NetworkPlugin().id)
        registry.register(ConsoleModel.shared, id: ConsolePlugin().id)
        server = DebugDrawerNetworkServer(registry: registry)
    }

    func enable() async throws {
        try await server.start()
    }
}
```

The server listens on a port the system picks and advertises itself over Bonjour as the device's
name. `DebugDrawerNetworkServerConfiguration` picks the name and the port, or `.loopback`
listens on 127.0.0.1 only and advertises nothing, for a viewer on the same Mac as a simulator.

When a viewer connects, the server lists it in `pairingRequests` with a new six-digit code.
`RemoteViewingPlugin` shows it in the drawer, where the person holding the device sees it: whether
the server listens and on which port, with Start Serving and Stop Serving, each viewer asking to
pair with its name, its code and a Reject button, and each paired viewer with a Disconnect button.
Its badge counts the viewers waiting for their code:

```swift
@MainActor
func showRemoteViewing(_ remote: RemoteViewing) {
    DebugDrawer.shared.registerGlobal(RemoteViewingPlugin(server: remote.server))
}
```

With the plugin listed, the app needn't call `enable()` at all: the person starts serving from the
drawer when they want a viewer in.

The person types the code into the viewer, which is then paired for as long as its connection
lasts. A wrong code, or anything sent before pairing, closes the connection; each code is good for
one try, and each try shows on the device. Pairing is remembered nowhere, so a viewer pairs again
after either app relaunches. Traffic is not encrypted: use it on a network you trust, in debug
builds.

**Versions.** The device's app and the viewer can come from different releases. Once paired, each
sends a hello naming the protocol's major version it speaks, the oldest it still speaks, and what
it can do (`commands`, `unsubscribe`, `acknowledgements`). Builds one major version apart
connect and use only what both have; two apart don't: the device closes the connection, and the
viewer's `connect` throws
`DebugDrawerTransportError.incompatibleVersion`. A message of a kind a build doesn't know is
dropped and logged once per kind, and the connection stays up. Nothing about the device moves
before pairing, the hello included. The same rules hold for a sidecar app over the socket and the
app-group store, whose files also carry a schema version and the writer's version, and are
migrated forward as they are read. A sidecar holds a `DebugDrawerSidecarTransport`, which uses the
socket while the app answers on it and the store while it doesn't, switching each way on its own
without losing a command or performing one twice ("Reaching a model from another process" in
Writing Global and Local Plugins).

**A sidecar on the Mac.** There both apps run at once, so the socket is the norm and the store the
fallback. Both apps find the group's container with `DebugDrawerAppGroupContainer`, sandboxed or
not: the app hands its `socketPath` and `storeDirectory` to its servers, and the sidecar hands
`socketPath(of:)` and `appDirectory(of:)`, naming the app by its bundle ID, to its transport. List
the group in each app's debug entitlements and sign both with the same team; on the Mac, prefix
the group with the team ID (or list a `group.` one in a provisioning profile), so macOS doesn't
ask whether one app may access another's data:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>TEAMID.com.example.debug</string>
</array>
```

If the system refuses the container (the sandbox without the group, a declined prompt, the
files' modes), the server's `start()` or the transport's initializer throws
`DebugDrawerTransportError.accessDenied`, whose `localizedDescription` says what to fix, and
nothing is written anywhere; a group with no container throws `noAppGroupContainer`. A sidecar
refused only the socket publishes `socketError` and reads the store.

On the Mac, `DebugDrawerNetworkBrowser` lists the devices advertising, and a
`DebugDrawerNetworkTransport` connects to one. It is a `DebugDrawerTransport`, so once paired it
hands out the same transports the plugins' views draw from:

```swift
@MainActor
func viewNetwork(of device: DebugDrawerNetworkDevice, code: String) async throws
    -> DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand> {
    let viewer = DebugDrawerNetworkTransport(endpoint: device.endpoint, viewerName: "Studio Mac")
    try await viewer.pair(code: code)
    return try await viewer.connect(toPlugin: NetworkPlugin().id, snapshot: NetworkSnapshot.self, command: NetworkCommand.self)
}
```

Or show the device with the plugins' own views. `NetworkPluginView(transport:)` and
`ConsolePluginView(transport:)` take the paired transport, or any `DebugDrawerTransport` (a
sidecar's too), show "Waiting for Network…" until the device's model answers, then draw what the
device's drawer draws, live, sending each filter, mock or clear back to the device. They intercept
and capture nothing on the Mac, and draw nothing in release builds:

```swift
struct DeviceView: View {
    let device: DebugDrawerNetworkTransport

    var body: some View {
        HStack(alignment: .top) {
            ScrollView { NetworkPluginView(transport: device) }
            ScrollView { ConsolePluginView(transport: device) }
        }
    }
}
```

The macOS example app has such a viewer under Debug > Remote Viewer: it lists the devices it finds
once you click Look for Devices, or connects to an address (`127.0.0.1:<port>` for a server on
loopback), asks for the code, and shows the device's Network and Console. The example apps serve
themselves through `RemoteViewingPlugin` in their drawer; launch them with `-ServeRemoteViewers` to start it at launch, plus
`-RemoteViewersOnLoopback` to listen on 127.0.0.1 alone.

**Info.plist.** iOS asks the person before an app uses the local network, and both the device's
app and the viewer must declare the service they advertise or browse for. Add to each:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Lets a Mac on your network show this debug build's logs and requests.</string>
<key>NSBonjourServices</key>
<array>
    <string>_debugdrawer._tcp</string>
</array>
```

Put them in the debug configuration's Info.plist only, as release builds never listen. A
sandboxed Mac app also needs the `com.apple.security.network.server` entitlement to serve, and
`com.apple.security.network.client` to view. Nothing else is needed for `.loopback`, which no
permission covers. Release builds get stand-ins: the server never listens, the browser finds
nothing and a viewer's pairing fails as unreachable.

### Sidecar sessions: commands only while someone is debugging

A registry made with `DebugDrawerSessions` acts on a sidecar's commands only within a session
the sidecar opens. Sessions expire, at most the host's maximum after they open; ending one, or
its expiry, reverts the changes the host declared session-scoped and keeps the persistent ones;
and every command is written to an audit log the host reads and forwards. Each capability's model
is registered with a `DebugDrawerChangeScope`: `.session(revertWith:)` names the command that
puts it back, `.persistent` keeps its changes. A model registered without one serves its
snapshots, and its commands are refused.

```swift
@MainActor
final class SidecarReceiver {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let registry: DebugDrawerModelRegistry
    let server: DebugDrawerAppGroupStoreServer
    private var forwarding: AnyCancellable?

    init(logLevels: LogLevelsModel, flags: FlagOverridesModel, container: URL) throws {
        registry = DebugDrawerModelRegistry(sessions: sessions)
        registry.register(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset))
        registry.register(flags, id: "MyApp.FlagOverrides", scope: .persistent)
        server = DebugDrawerAppGroupStoreServer(registry: registry, directory: container.appending(path: "DebugDrawer"))
        forwarding = sessions.auditEntries.sink { entry in
            AuditForwarder.send(entry)
        }
        try server.start()
    }
}
```

The library draws nothing: `sessions.snapshot` is a `DebugDrawerSessionState`, published as it
changes, and the app shows its own indicator, in its own style, for as long as it is active, so
the person holding the device always knows debug tooling is engaged:

```swift
struct SessionIndicator: View {
    @ObservedObject var sessions: DebugDrawerSessions

    var body: some View {
        if let session = sessions.snapshot.session {
            HStack {
                Text("Debug session until \(session.expires, style: .time)")
                Button("End") { sessions.end() }
            }
        }
    }
}
```

A sidecar opens a session by connecting to `DebugDrawerSessions.pluginID` like any plugin, with
`DebugDrawerSessionState` snapshots and `DebugDrawerSessionCommand` commands, and sending
`.open(duration:)`; it ends it with `.end`. A command sent while no session is open, after it
ended or expired, to a model registered without a scope, or to no model, is refused and changes
nothing, over the socket and the store alike. A refusal is final: the app still acknowledges the
command, so `DebugDrawerSidecarTransport` doesn't send it again when it switches channels, and a
sidecar sends it anew once a session is open. A session asked to last longer than the maximum expires at the maximum, and one asked to
open while another is open is refused. Expiry is a one-shot timer at the expiry date, and a
command that arrives after it, before a suspended app's timer has fired, expires the session
first. The app's own drawer, in the process, is not gated.

Each `DebugDrawerAuditEntry` holds its date, the session's ID, the capability (the ID the model
was registered under, or `DebugDrawerSessions.pluginID` for a session opening or ending) and the
event: `sessionOpened(expires:grant:)`, `sessionEnded` (`.ended`, `.expired`, or `.disabledByHost` as a receiver's gate turns off), `commandApplied`,
`commandRefused` with its reason, or `changeReverted`. It never holds what a command carried. It
is `Codable` for forwarding as JSON. `auditLog` keeps the newest 1,000 entries in memory
(`auditCapacity` sets another bound), and `auditEntries` publishes every entry as it is recorded.
The sessions are real in every build, as the receiver below uses them; in a release build the
drawer's registry and servers are stand-ins that never reach them, so only a
`DebugDrawerReceiver` opens one there.

### Production builds: the receiver

A release build gets none of the drawer. To let an employee-only sidecar app reach a production
app, the app links one more product, `DebugDrawerReceiver`: UI-less, with no interception, no
plugin and no dependency on the drawer (and, to offer tweaks, `DebugDrawerTweaks`, to mirror
analytics events, `DebugDrawerAnalytics`, for translators and accessibility reviewers,
`DebugDrawerLocalization` and `DebugDrawerAccessibility`, to forward crash reports and
MetricKit payloads, `DebugDrawerMetricKit`, to mock responses for a session, `DebugDrawerNetwork`,
to show the push token for test pushes, `DebugDrawerNotifications`, to record hangs and
signposts, `DebugDrawerHangDetector`, to spoof its location for a session, `DebugDrawerLocation`,
or to show a snapshot of the app's state, `DebugDrawerAppInfo`, below). It serves a sidecar, over the app group's store, only the
capabilities the app enables, within sessions the sidecar opens, and refuses everything else.
Before shipping it, read the receiver's "Security Model and Distribution" article
([`SecurityModel.md`](Sources/DebugDrawerReceiver/DebugDrawerReceiver.docc/SecurityModel.md)): what
the receiver trusts (the team's signature and the app group, on iOS and on the Mac), what someone
holding the sidecar can do with each capability below, how to distribute the sidecar (TestFlight
internal testers or a private Apple Business Manager app, never an Enterprise account or a public
TestFlight link), and what to tell App Review.

```swift
import DebugDrawerReceiver

@MainActor
final class FlagServiceAdapter: DebugDrawerFeatureFlagAdapter {
    private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        [DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false))]
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

@MainActor
final class ProductionReceiver {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(flags: FlagServiceAdapter, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        try receiver.start()
    }
}
```

Add it to the production target alone (`.product(name: "DebugDrawerReceiver", package:
"DebugDrawer")`); the drawer and its plugins stay in the debug configuration. `container` is the
app group's container, `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`,
which the sidecar app shares. The receiver keeps to the app's own directory of that store,
`DebugDrawer/apps/<bundle ID>/` (`receiver.appDirectory`), named by the main bundle's identifier,
so several apps of a company can share one group and one sidecar ("Several apps, one sidecar"
below). The sidecar reaches the receiver with a `DebugDrawerSidecarTransport` (or a
`DebugDrawerAppGroupStoreTransport`) on that app's directory
(`DebugDrawerAppGroupContainer.appDirectory(of:)`), opens a session through
`DebugDrawerSessions.pluginID`, then connects to `DebugDrawerFeatureFlagOverrides.pluginID`. The
receiver serves the store only, not the socket.

What the receiver does:

- **Nothing until enabled.** With no capability enabled every command is refused, opening a
  session included. A command to an ID the app didn't enable, or disabled with `disable(_:)`, is
  refused even inside an open session. Each refusal is logged and written to the sessions' audit
  log (`commandRefused(.unknownCapability)`).
- **Capabilities are models.** `.featureFlagOverrides(adapter)` overrides the flags the adapter
  lists, and only with a value of the kind the flag has (`.experimentOverrides(adapter)`, below,
  forces the experiments it lists into one of their variants, and `.logLevels(adapter)` raises the
  log subsystems it lists); `clearAllOverrides` clears only the
  overrides it set, never the app's own. `.model(_:id:scope:)` serves any
  `DebugDrawerPluginModel` of the app's. A command decodes into the model's own `Command` type or
  is refused as malformed; nothing received is run or evaluated, and a sidecar reads only the
  model's snapshot, so list nothing secret in it.
- **Scopes.** Each capability takes a `DebugDrawerChangeScope`: `.session(revertWith:)` reverts it
  as the session ends or expires (feature flag overrides default to `.session(revertWith:
  .clearAllOverrides)`), `.persistent` keeps it.
- **The app draws the indicator.** Observe `sessions.snapshot` as in "Sidecar sessions" above.

**Feature flag overrides in production.** The risk: an employee holding the sidecar can turn on,
on their own device, a feature that hasn't been released. An override changes only what the app
reads through the adapter, so a flag the server enforces (an entitlement it checks, content it
serves only when the flag is on) stays enforced by the server. It is off until the app calls
`enable(.featureFlagOverrides(adapter))`, and the app marks which flags an employee may override
by listing them, and only them, in the adapter's `overridableFlags()`: a command for any other
flag is refused as `commandRefused(.notExposed)`, one with a value of another kind than the flag's
as `commandRefused(.malformedCommand)`, and neither reaches the adapter. Each override and each
clear is audited as `commandApplied`, and the session's revert as `changeReverted`. A command the
sidecar leaves while the app is in the background is applied as the app comes to the foreground.
With the default scope the overrides are cleared as the session ends or expires, and those a
session left because the app quit during it are cleared as the next launch makes the capability,
so make it at startup; with `scope: .persistent` they stay until a sidecar clears them, across
launches when the adapter keeps its overrides. `DebugDrawerFeatureFlagOverrides` keeps the keys it
overrode (never their values) in the standard defaults, or in those passed to
`init(adapter:defaults:)`, so a relaunched app still lists and clears them.

**Experiment overrides in production.** Employees can see each arm of an A/B test on a release
build: `enable(.experimentOverrides(adapter))` serves a sidecar the experiments the app's
`DebugDrawerExperimentAdapter` lists in `overridableExperiments()`, each with its variants and the
variant the app is assigned now (`DebugDrawerExperiment`), and within a session forces one of
those variants (`DebugDrawerExperimentOverrides.Command.setOverride(experiment:variant:)`). The
risk: a forced variant isn't a real assignment, so the device's events would pollute the
experiment's data. The exclusion hook guards against it: the adapter must implement
`overriddenExperimentsDidChange(_:)`, which hears the overridden experiments' keys as the model is
made (overrides kept from the last launch included) and at every change, empty once none is left;
while it holds any, leave the session or user out of the experiments' analysis.
`DebugDrawerExperimentOverrides.isExcludedFromAnalytics` and `overriddenExperiments` say the same at
any time, from any thread, for an analytics pipeline that tags events on its own queue (make the
model, then `enable(.experimentOverrides(model))`). It is off until the app enables it: a command
to it before then is refused as `commandRefused(.unknownCapability)`, even inside a session. An
experiment the adapter doesn't list is refused as `commandRefused(.notExposed)`, a variant the
experiment doesn't have as `commandRefused(.malformedCommand)`, and neither reaches the adapter.
Audit, foreground delivery, scopes and the keys kept across launches work as for feature flag
overrides: by default the overrides are cleared, and the exclusion lifted, as the session ends;
with `scope: .persistent` the device stays excluded across launches until a sidecar clears them.

**Log levels in production.** To read what a release build logs at a verbose level while an
employee reproduces a problem, a sidecar can raise chosen subsystems of the app's own logger for
its session. An app can't change the level unified logging (os_log) keeps for its subsystems; its
logger can, so the hook is the app's: `enable(.logLevels(adapter))` serves a sidecar the subsystems
the app's `DebugDrawerLogLevelAdapter` lists in `elevatableSubsystems()`, each a
`DebugDrawerLogSubsystem` with the levels a sidecar may set (the logger's own names, such as
`"info"`, `"debug"`, `"trace"`) and the level it logs at now, and within a session sets one
(`DebugDrawerLogLevels.Command.setLevel(subsystem:level:)`), calling the adapter's
`setLevel(_:forSubsystem:)`; `reset(subsystem:)` and `resetAll` call `resetLevel(forSubsystem:)`
for the subsystems it raised, never one the app raised itself.

- **The risk: personal data in verbose lines.** Verbose levels log more of what the app handles.
  The capability captures no log line and sends none to the sidecar: the raised lines go where the
  app's logger already writes them, through the redaction it applies to every line (os_log's
  `privacy: .private` interpolations, a swift-log handler that masks fields), so keep that
  redaction on at the verbose levels too. To read the lines from the sidecar, forward them to a
  diagnostics capture as well (below), which redacts them itself. In a debug build, a logger bridged to the Console
  through `ConsoleLogSink` shows the raised lines in the drawer as logged.
- **Off by default, and only what the app lists.** Until the app enables it, a command to it is
  refused as `commandRefused(.unknownCapability)`, even inside a session. A subsystem the adapter
  doesn't list is refused as `commandRefused(.notExposed)`, a level the subsystem doesn't list as
  `commandRefused(.malformedCommand)`, and neither reaches the adapter. Each change is audited as
  `commandApplied`.
- **For the session, always.** As the session ends, expires (at the sessions' maximum duration or
  the grant's expiry) or a gate turns it off, the adapter is told to reset each subsystem the
  sidecar raised, audited as `changeReverted`; there is no persistent scope. `DebugDrawerLogLevels`
  keeps the names of the subsystems it raised (never their levels) in the standard defaults, or in
  those passed to `init(adapter:defaults:)`, so levels a session left when the app quit or was
  killed are reset as the next launch makes the capability: make it at startup.

**Diagnostics capture in production.** To see what a release build logs and sends while an
employee reproduces a problem, the app hands a `DebugDrawerDiagnosticsCapture` its log lines and
its requests, and a sidecar that starts the capture in its session reads them, redacted, and puts
them in its bug report:

```swift
let capture = DebugDrawerDiagnosticsCapture(sessions: sessions)
receiver.enable(.diagnosticsCapture(capture))

// The app's logger's backend:
capture.log(level: .error, message: "Payment declined", metadata: ["order": "1042"], subsystem: "com.example.shop")

// The app's networking code, once it has the outcome:
let started = Date()
let (data, response) = try await session.data(for: request)
capture.record(request, response: response, body: data, started: started)
```

- **The risk: real customers' data on disk.** What the app logs and sends belongs to the person
  using it, and a capture keeps it in the app group's container, which every app of the group can
  read, until it is deleted. The capture limits that four ways.
- **Nothing outside a session.** Until a sidecar sends `DebugDrawerDiagnosticsCapture.Command.start`
  in an open session (with a grant listing the capability, under a grant policy or after
  `.requiringGrant()`), `log` and `record` do nothing and evaluate none of their arguments, and a
  session opened for anything else captures nothing. Nothing is intercepted, ever: no os_log
  reading, no URL protocol, no swizzling; the app hands over what it already has, after its own
  call, so a request is never sent again and nothing it sees changes. Until the app enables the
  capability, `start` is refused as `commandRefused(.unknownCapability)`.
- **Redacted, then kept.** Each line and request is redacted on the calling thread before it is
  kept anywhere, by `DebugDrawerDiagnosticsRedaction` (`.standard` unless the app passes its own,
  `.standard.adding(headers:keys:jsonPaths:values:)`): the `Authorization`, `Proxy-Authorization`,
  `Cookie` and `Set-Cookie` headers; values under keys containing `token`, `secret`, `password`,
  `session`, `auth`, `apikey`, `email` or `phone` (headers, URL query items, JSON keys at any
  depth, a log line's metadata); JSON paths the app lists; a URL's user and password; and, in the
  message, metadata values, header values, the URL's path, query and fragment and JSON strings, the
  text that is an email address, a JSON Web Token, a `Bearer` credential or a secret written as
  `password=…`. A body is kept only when it is JSON, redacted the same way; any other body (a form,
  a multipart upload, an image) is left out with only its size. A failure keeps its error domain
  and code, never its message. Subsystem and category names are kept as the app wrote them.
- **Bounded.** `DebugDrawerDiagnosticsCapture.Limits` (`.standard`: 1,000 lines, 200 requests,
  bodies up to 64 KiB, 2 MiB of text in all) drops the oldest entries first and counts what it
  dropped; a larger body is left out.
- **Deleted with the session.** The capture lives in memory and in the capability's snapshot file
  in the app's own directory of the store, nowhere else, and both are deleted as the sidecar sends
  `stop`, as the session ends or expires, as a gate turns the capability off (audited as
  `changeReverted`), and, after a launch killed during a session, as the next launch enables the
  capability, so enable it at startup. When the sidecar makes its report it copies the capture in
  (`Snapshot.consoleLog`, `Snapshot.networkJSON`) and sends `export`, which the app records in
  `Snapshot.exports` (when, how many lines and requests) and the audit log as `commandApplied`; that
  copy, in the sidecar's report, is the only one that outlives the session. The app keeps no copy
  for having exported it.

Show `capture.snapshot.isCapturing` in the app's session indicator. In the sidecar, the kit's
`DebugDrawerSidecarPlugin.diagnosticsCapture` offers Start Capture, shows the capture, and adds it
to the report.

**Bug reports from the production app.** For dogfooding on the build that ships: with their
sidecar's session open, an employee who hits a problem triggers a report in the app, which takes a
screenshot of its own key window, the diagnostics capture's recent lines and a state snapshot of
the app's choosing, and hands them to the sidecar, where the employee annotates the report and
sends it through the sidecar's uploader. The library adds no trigger: call `trigger(note:)` from
one of your own, a shake handler, a Feedback menu item, a button on an internal screen:

```swift
struct CheckoutState: Encodable {
    let screen: String
    let cartItems: Int
}

let reports = DebugDrawerBugReports(sessions: sessions, diagnostics: capture) {
    CheckoutState(screen: "checkout", cartItems: 2)
}
receiver.enable(.bugReports(reports))

// The app's own trigger, such as its shake handler:
reports.trigger(note: "Shaken on the checkout screen")
```

- **The risk: what was on screen.** A report holds what the employee had on screen, which can't be
  redacted (it is an image, drawn by the app from its own window: no screen capture, nothing of
  another app or the system), plus the app's log lines and its state, which are. The capability
  limits that four ways.
- **Off unless enabled, and no trigger of its own.** Until the app enables `.bugReports(_:)`, a
  trigger in a session is refused as `unknownCapability`; nothing in the library calls
  `trigger(note:)`, so with no trigger of the app's own nothing is ever taken.
- **Only in a session, through the same gates as a command.** Outside a session `trigger(note:)`
  returns `.refused(.noActiveSession)` at once: it draws nothing, reads no state and writes no
  audit entry, so a trigger left wired up for every user does nothing for a customer. In a session,
  a trigger meets the receiver's and the capability's gates (`receiverDisabled`,
  `capabilityDisabled`) and, under a grant policy or after `.requiringGrant()`, needs a grant that
  lists `DebugDrawerBugReports.pluginID`; a report taken is audited as `commandApplied`.
- **The app never uploads.** A report goes only into the capability's snapshot in the app's own
  directory of the store, which the sidecar reads; the sidecar sends it. `DebugDrawerReceiver`
  depends on no other module, so a production app that links it links no uploader
  (`DebugDrawerReportUploader` is in `DebugDrawer`, which a release build doesn't link).
- **Redacted, bounded, and deleted with the session.** The note and the state (encoded as JSON) are
  redacted by `DebugDrawerDiagnosticsRedaction` (`.standard` unless the app passes its own); the
  log lines are the diagnostics capture's, redacted there, and only while a sidecar started that
  capture in the session (otherwise `logs` is `.notCapturing`). `DebugDrawerBugReports.Limits`
  (`.standard`: 3 reports, the newest 200 lines each, 64 KiB of state, 4 MiB of screenshot, drawn
  again at one pixel per point before it is left out) drops the oldest report first and leaves out
  a larger state or screenshot with its size. Reports are deleted as the session ends or expires
  (audited `changeReverted`), as a gate turns the capability off, as the sidecar deletes one, and,
  after a launch killed during a session, as the next launch enables the capability, so enable it
  at startup. `export(id:)` records that the sidecar took a copy (`Snapshot.exports`, audited
  `commandApplied`); the app keeps no copy for it.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.bugReports` shows each report with an
annotation field and Include in Report; Create Report puts the report picked (the newest unless
another is) in the zip, under `Bug Reports/` (`screenshot.png`, `note.txt` with the app's note and
the annotation, `console.txt`, `state.json`), and Send Report sends it through
`DebugDrawer.shared.reportUploader`.

**Scenarios: launching the app into a state.** To reach a screen deep in a release build ("open
order 123", "show the paywall", "onboarding step 3") without tapping through it, the app registers
named scenarios, each with the parameters it takes and a handler of its own that puts the app
there; the sidecar lists them, with a field for each parameter, and Launch brings the app to the
foreground and runs the handler:

```swift
@MainActor
final class ShopRouter {
    private(set) var screen = "Home"

    func openOrder(_ id: Int) { screen = "Order \(id)" }
    func showPaywall(plan: String) { screen = "Paywall (\(plan))" }
}

@MainActor
final class ProductionScenarios {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(router: ShopRouter, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.scenarios([
            DebugDrawerScenario("open-order", title: "Open Order", parameters: [
                .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999)
            ]) { arguments in
                router.openOrder(arguments.integer("orderID") ?? 123)
            },
            DebugDrawerScenario("show-paywall", title: "Show Paywall", parameters: [
                .choice("plan", title: "Plan", options: ["monthly", "annual"])
            ]) { arguments in
                router.showPaywall(plan: arguments.string("plan") ?? "monthly")
            }
        ], launchURL: URL(string: "shop-internal://")))
        try receiver.start()
    }
}
```

- **The risk: whatever the handlers allow.** An employee holding the sidecar can put their own
  device in any state a registered scenario reaches, with any value its parameters take. Register
  only scenarios fit for production, bound each parameter tightly, keep the server's own checks
  where a handler reaches it, and add `.requiringGrant()` to the capability when team signing
  alone isn't enough.
- **Off by default, and only what the app declares.** Until the app enables `.scenarios(_:)`, a
  launch is refused as `commandRefused(.unknownCapability)`, even inside a session. The receiver
  passes a handler only a registered scenario's ID and values for the parameters that scenario
  declares (`DebugDrawerScenarioParameter`: `.string(_:maximumLength:)`, `.integer(_:in:)`,
  `.boolean(_:)`, `.choice(_:options:)`), each checked against its kind and bounds, and evaluates
  nothing it receives. A scenario the app didn't register is refused as
  `commandRefused(.notExposed)`; a parameter the scenario doesn't declare, a value of another kind,
  outside the range, longer than the maximum or not among the options as
  `commandRefused(.malformedCommand)`; neither runs a handler. A declared parameter the launch
  leaves out takes its default. The handler reads the values typed:
  `arguments.integer("orderID")`, `string(_:)`, `boolean(_:)`.
- **Within a session, audited, and not reverted.** A launch is performed only in an open session
  and audited as `commandApplied`; `DebugDrawerScenarios.Snapshot.lastRun` tells the sidecar it
  ran. What a handler did lasts past the session: the library can't undo it.
- **Bringing the app forward.** The sidecar opens `launchURL`, a URL of the app's own scheme
  (`CFBundleURLTypes`), to bring the app to the foreground; on the Mac it opens the app by its
  bundle identifier instead. The receiver doesn't depend on it: the launch waits in the store and
  is performed as the app comes to the foreground, however it got there, or at once when it is
  already there. The URL's own handling is the app's; it needn't do anything with it.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.scenarios` lists the scenarios with a field
for each parameter (a text field, a number field, a switch or a picker) and a Launch button, which
sends the launch and then opens the app (`DebugDrawerSidecarApp.open(url:)`).

**Auth actions: expired tokens, refreshes and log outs.** To test how a release build handles its
access token expiring, a forced refresh or a log out, the app registers actions on its own sign-in,
each a handler of its own that takes nothing and says what it came to; the sidecar lists them, a
button each with the last result:

```swift
@MainActor
final class AuthService {
    private var accessToken: String? = "access-token-from-the-server"
    private(set) var state = "Signed in"

    func expireAccessToken() { state = "Expired" }
    func refresh() async -> Bool {
        guard accessToken != nil else { return false }
        accessToken = "a-new-access-token"
        state = "Signed in"
        return true
    }
    func logOut() {
        accessToken = nil
        state = "Signed out"
    }
}

@MainActor
final class ProductionAuthActions {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(auth: AuthService, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.authActions([
            .expireAccessToken {
                auth.expireAccessToken()
                return .succeeded
            },
            .forceRefresh {
                await auth.refresh() ? .succeeded : .failed("Not signed in")
            },
            .logOut {
                auth.logOut()
                return .succeeded
            }
        ], launchURL: URL(string: "shop-internal://")))
        try receiver.start()
    }
}
```

- **The risk: low.** An employee holding the sidecar can expire, refresh or end the sign-in of the
  app on their own device, and so log themselves out. An action of your own that reaches further
  (`DebugDrawerAuthAction(_:title:summary:handler:)`, such as ending every session on the server)
  deserves `.requiringGrant()` on the capability.
- **Off by default.** Until the app enables `.authActions(_:)`, a request is refused as
  `commandRefused(.unknownCapability)`, even inside a session; an action the app didn't register
  as `commandRefused(.notExposed)`, running nothing.
- **No credential crosses to the sidecar.** The receiver never sees a token: it runs the app's
  handler, which receives nothing from the sidecar, and hands back only what it came to,
  `DebugDrawerAuthActions.Status` (`running`, `succeeded`, `failed(message:)`). A failure's
  message is a `StaticString`, text written in the app's source, so no value the app holds at run
  time can reach the sidecar through it; write what a tester reads ("Not signed in"). The
  snapshot holds the actions' IDs, titles, summaries and last runs, and nothing else.
- **Within a session, audited, and not reverted.** A request is performed only in an open session
  and audited as `commandApplied`; what the action did lasts past the session. A request left while
  the app is in the background runs as it comes to the foreground; the sidecar opens `launchURL`
  (on the Mac, the app by its bundle identifier) to bring it there, as for scenarios.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.authActions` lists the actions with a button
each, which sends the request and then opens the app, and each action's last run: running,
succeeded, or failed with the app's message.

**Resetting the app's state: defaults, files, caches and cookies.** To get a production build back
to a fresh install on an employee's own device without reinstalling it, the app allows the
categories a sidecar may clear, the same ones the Reset App State plugin clears in a debug build;
the sidecar lists what each holds, confirms exactly that, and the app clears it as it next comes to
the foreground. It lives in `DebugDrawerAppStateReset`, which a release build links beside the
receiver (it links WebKit for the cookies; the receiver doesn't):

```swift
import DebugDrawerAppStateReset
import DebugDrawerReceiver

@MainActor
final class ProductionReset {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.appStateReset(AppStateResetRequests(
            sessions: sessions,
            allowing: [.userDefaults, .caches, .urlCache, .cookies],
            launchURL: URL(string: "shop-internal://")
        )))
        try receiver.start()
    }
}
```

- **The risk: data loss.** A reset deletes what the app holds on the device it runs on, and it can't
  be brought back: a tester's drafts, downloads and sign-in go with it. Allow only the categories a
  tester needs; an app that allows only `.caches` (and `.urlCache`) lets a sidecar clear its caches
  and nothing else. Consider `.requiringGrant()` on the capability, so only a sidecar your server
  vouches for may reset.
- **Off by default.** Until the app enables `.appStateReset(_:)`, a request is refused as
  `commandRefused(.unknownCapability)`, even inside a session; a category the app didn't allow as
  `commandRefused(.notExposed)`, deleting nothing.
- **App groups too.** Files and Caches also clear the containers of the app's groups (less
  their preferences, and the receiver's store), and other apps of a group share its container,
  so a reset of one app deletes what they keep there. Give the app a group of its own if that
  matters.
- **The keychain only when asked for by name.** `.all` holds every category but the keychain, and
  naming `.keychain` in `allowing:` traps; the app allows it with `allowingKeychain: true` alone,
  and then the listing names each item by its service or label, never its account.
- **The confirmation lists what will be deleted, and nothing else is.** Nothing is read until the
  sidecar asks, in a session. The snapshot lists each category's keys, top-level files and folders
  with their sizes, cookie domains and keychain services (at most 500 a category, with a count of
  the rest), never a value. A reset carries the categories confirmed and the revision of each that
  the confirmation showed; one at another revision is refused as
  `commandRefused(.staleConfirmation)`, and when what a category holds changes before the reset
  runs, the app deletes nothing and reports the categories that changed. A size changing doesn't
  count; a key, file, domain or item coming or going does.
- **On the next foreground, then reported.** A confirmed reset waits until the app is in the
  foreground, runs at once when it already is, and is dropped when the session ends first or the
  app quits; the sidecar opens `launchURL` (on the Mac, the app by its bundle identifier) to bring
  it there. The snapshot's `lastReset` reports what each category cleared and what it couldn't
  delete, and why. The app keeps running; restart it yourself if it caches what was cleared.
- **What stays.** DebugDrawer's own state (the keys starting `com.debugdrawer.` or `DebugDrawer.`
  and the files named `DebugDrawer…`), and the receiver's store, so the session, its audit log and
  the sidecar's view of the app survive the reset. A request is performed only in an open session
  and audited.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.appStateReset` lists the allowed categories
with a checkbox each and what it would clear; Review Reset… opens a confirmation listing every
item, and Reset sends it and then opens the app (`DebugDrawerSidecarApp.open(url:)`). While the
reset waits for the app it can be canceled; then the plugin shows what was cleared.

**Turning it off remotely.** To shut every sidecar out without a release (a leaked sidecar app,
say), give the receiver a gate backed by your own remote configuration, and a capability one of
its own; the library calls no configuration service itself (`RemoteConfig` here stands for yours):

```swift
@MainActor
final class GatedReceiver {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(config: RemoteConfig, flags: FlagServiceAdapter, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions) {
            config.bool("sidecar_enabled")
        }
        receiver.enable(.featureFlagOverrides(flags)) { config.bool("sidecar_flag_overrides") }
        config.onUpdate { [receiver] in receiver.reevaluateGates() }
        try receiver.start()
    }
}
```

- **The receiver's gate first.** `isAllowed` (set at `init(directory:sessions:isAllowed:)` or
  later) is asked before anything else at every command, a session's opening included, so before
  any grant is verified. While it
  returns `false` every command is refused as `commandRefused(.receiverDisabled)`, the open
  session ends as `sessionEnded(.disabledByHost)`, reverting its session-scoped changes, and no
  capability's snapshot is written: each one's file leaves the store. The sessions' snapshot
  stays, so the sidecar sees its session end.
- **A capability's gate.** `enable(_:isAllowed:)` gates one capability. While it returns `false`
  that capability's commands are refused as `commandRefused(.capabilityDisabled)`, its snapshot
  leaves the store, and its session-scoped change in the open session is reverted at once
  (`changeReverted`); the session and the other capabilities carry on.
- **When it takes effect.** A closure can't announce a change, so the receiver asks the gates at
  each command, as it starts, as the app comes to the foreground and before writing a snapshot.
  Call `reevaluateGates()` as your configuration updates, as above, to end an open session at
  once, with no command needed. A gate turned back on serves the snapshots again, and a new
  session can open. Nothing polls.

**Tweaks in production.** A tweak marked `.productionSafe()` where it is declared can be changed
from the sidecar in a release build; every other tweak stays debug-only. Link
`DebugDrawerTweaks` (`.product(name: "DebugDrawerTweaks", package: "DebugDrawer")`) beside the
receiver, the UI-free half of the Tweaks plugin, and enable the capability with the tweaks a
sidecar may change:

```swift
import DebugDrawerTweaks

enum AppTweaks {
    static let backend = Tweak.picker("Backend", key: "backend", default: Backend.production).productionSafe()
    static let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
}

receiver.enable(.tweaks(AppTweaks.backend, AppTweaks.newCheckout))
```

- **Only production-safe tweaks.** The sidecar connects to `TweaksModel.pluginID` and its
  `TweaksModel.Snapshot` lists only the tweaks marked `.productionSafe()` (here `backend`), each
  with its title, key, control, default and current value. A `setValue` or `reset` naming any
  other key, `newCheckout` included, is refused as `commandRefused(.notExposed)` even inside a
  session, and a value that isn't one of the tweak's (a removed option, a number outside a
  stepper's range, a string for a toggle) as `commandRefused(.malformedCommand)`; both are logged
  and audited and change nothing.
- **Values persist and reach the app.** A change goes into the tweaks' storage (the standard
  defaults, or the `storage:` you pass, the same as `installTweaks(storage:)`'s), so
  `AppTweaks.backend.value` and its `publisher` return it, now and after a relaunch. In a release
  build a production-safe tweak reads its stored value only once the app has made the capability,
  so make it at startup before reading tweaks; an app that never makes it reads every default, as
  before.
- **Persistent by default.** Pass `scope: .session(revertWith: .resetAll)` to reset the
  production-safe tweaks to their defaults when the session ends instead. A session the app was
  killed in leaves them as the sidecar set them: unlike the other session-scoped capabilities,
  tweaks aren't reset as the next launch makes the capability.

**Analytics events in production.** While a sidecar's session is open, the events the app records
through `AnalyticsEvents.record` can be mirrored to the sidecar, so QA can check tracking on the
build that ships. It is off unless the app enables it. Link `DebugDrawerAnalytics`
(`.product(name: "DebugDrawerAnalytics", package: "DebugDrawer")`) beside the receiver, the
UI-free half of the Analytics plugin, which holds `AnalyticsEvents` and `AnalyticsValue`, and
enable the capability with the redaction rules for the app's events:

```swift
import DebugDrawerAnalytics
import DebugDrawerReceiver

@MainActor
final class ProductionAnalyticsMirror {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.analyticsEvents(
            sessions: sessions,
            redaction: .standard.adding(keys: ["customer_name"], values: [#"\bACCT-\d{6}\b"#])
        ))
        try receiver.start()
    }
}

// Wherever the app sends an event, in every build:
AnalyticsEvents.record("checkout_completed", properties: ["plan": "pro", "seats": 3], source: "Segment")
```

- **Only during a session.** The sidecar connects to `AnalyticsEventsMirror.pluginID`; its
  `AnalyticsEventsMirror.Snapshot` holds the open session's ID and the events recorded since it
  opened, oldest first, each with its place in the session's order, time, name, properties and
  source. Nothing recorded before the session opens is kept for it, and as the session ends or
  expires the list empties and nothing more is mirrored, even an event recorded after the expiry
  date before the system's timer fires. The snapshot keeps the session's newest 1,000 events
  (`capacity:`); `AnalyticsEventsMirror.Command.clear` drops those already read. While no session
  is open, `record` in a release build evaluates none of its arguments. Under a grant policy only
  a session whose grant lists `AnalyticsEventsMirror.pluginID` is mirrored events; a session whose
  grant doesn't is served its ID and no events, and nothing recorded during it is kept.
- **Redacted in the app.** Each event is redacted on the thread that records it, before it is kept
  anywhere, so no unredacted value reaches the snapshot, the store's files or the audit log
  (which never holds an event). `AnalyticsRedaction.standard` masks the value of any property
  whose key contains `email`, `phone`, `token`, `secret`, `password`, `session`, `auth` or
  `apikey`/`api_key`/`api-key` (ignoring case, at any depth, an object or array under it whole),
  and any string value holding an email address or a JSON Web Token; an event name or source a
  value pattern matches is masked too. `adding(keys:values:)` adds key substrings and regular
  expressions (`NSRegularExpression` syntax, ignoring case; an invalid one traps), and
  `AnalyticsRedaction(keys:values:)` starts from none. A masked value becomes `"[REDACTED]"`.
  Phone numbers in free text aren't matched by default: add a pattern for the formats your app
  sends.

**Localization review in production.** A translator working on the build that ships can show
each string's key, to name the one to fix, or pseudo-localized text, to find what clips or was
never translated, from the sidecar, for the session. Link `DebugDrawerLocalization`
(`.product(name: "DebugDrawerLocalization", package: "DebugDrawer")`) beside the receiver, the
UI-free half of the Localization plugin, read the strings a reviewer should see through
`LocalizationReview`, and enable the capability:

```swift
import DebugDrawerLocalization
import DebugDrawerReceiver
import SwiftUI

@MainActor
final class ProductionLocalizationReview {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.localizationReview())
        try receiver.start()
    }
}

struct SettingsHeader: View {
    let itemCount: Int

    var body: some View {
        VStack {
            Text(LocalizationReview.shared.localizedString("settings.title"))
            Text(LocalizationReview.shared.localizedString("\(itemCount) items"))
        }
    }
}

// The app's root view, redrawn as the mode changes:
// ContentView().localizationReview()
```

- **The sidecar sets the mode.** It connects to `LocalizationReview.pluginID`; the
  `LocalizationReview.Snapshot` holds the mode (`standard`, `showingKeys` or `pseudoLocalized`),
  and `LocalizationReview.Command.setMode(_:)` sets it, within a session only. Outside one, or in
  an app that hasn't enabled it, the command is refused and audited, and every string shows its
  translation.
- **Session-scoped, always.** As the session ends or expires the mode returns to `standard`. A
  host can't keep it longer: a mode left on would show keys or accented text to whoever holds the
  device next.
- **What it covers.** Only strings the app reads through `LocalizationReview`:
  `localizedString(forKey:value:table:bundle:)`, which asks the bundle as
  `Bundle.localizedString(forKey:value:table:)` does, and `localizedString(_:)`, which takes a
  `LocalizedStringResource` and resolves it as `String(localized:)` does, arguments and plural
  variant included, before the mode applies. Show them in a SwiftUI `Text`, a UIKit label or
  anywhere else. `.localizationReview()` on the root view gives it a new identity as the mode
  changes, so every body reads its strings again (and its `@State` starts over); a UIKit screen
  observes `LocalizationReview.shared.$snapshot` and reloads its text.
- **What it doesn't.** Nothing is intercepted in a release build, so the strings the app looks up
  any other way stay translated: `Text("key")` and every `LocalizedStringKey`,
  `String(localized:)` and `NSLocalizedString` called directly, storyboards and XIBs,
  `Info.plist` strings, and the system's own text. A plural read through
  `localizedString(forKey:...)` loses its variants when pseudo-localized; read it through
  `localizedString(_:)`.

**Accessibility overrides in production.** An accessibility reviewer can try the shipping build at
another Dynamic Type size, with Increase Contrast or with Reduce Motion, from the sidecar, without
changing the device's settings, for the session. Link `DebugDrawerAccessibility`
(`.product(name: "DebugDrawerAccessibility", package: "DebugDrawer")`) beside the receiver, apply
the overrides to the app's root view, and enable the capability:

```swift
import DebugDrawerAccessibility
import DebugDrawerReceiver
import SwiftUI

@MainActor
final class ProductionAccessibilityReview {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.accessibilityEnvironmentOverrides())
        try receiver.start()
    }
}

struct ReviewedRoot: View {
    var body: some View {
        Text("Order history")
            .accessibilityEnvironmentOverrides()
    }
}
```

- **The sidecar sets the values.** It connects to `AccessibilityEnvironmentOverrides.pluginID`;
  the `AccessibilityEnvironmentOverrides.Snapshot` holds each override (`dynamicTypeSize`,
  `increaseContrast`, `reduceMotion`), `nil` while the system's value applies, and
  `setDynamicTypeSize(_:)`, `setIncreaseContrast(_:)`, `setReduceMotion(_:)` and `reset` change
  them, within a session only; outside one, or in an app that hasn't enabled it, they are refused
  and audited.
- **Session-scoped, always.** As the session ends or expires every value is the system's again.
- **SwiftUI views only.** The modifier sets `dynamicTypeSize`, `colorSchemeContrast` and
  `accessibilityReduceMotion` in the environment of the views under it, through SwiftUI's public
  modifiers and the settable keys previews use, so a view that reads them, and every text style,
  follows. UIKit and AppKit views read the system's settings and don't see the overrides.

**Crash reports and MetricKit payloads in production.** A dogfooder's crash can reach the team
through the sidecar, without a crash SDK's dashboard: the app keeps the MetricKit payloads it
receives, crash diagnostics among them, and serves them to the sidecar's next session. It is off
unless the app enables it. Link `DebugDrawerMetricKit` (`.product(name: "DebugDrawerMetricKit",
package: "DebugDrawer")`) beside the receiver, the UI-free half of the MetricKit plugin, and enable
the capability:

```swift
import DebugDrawerMetricKit
import DebugDrawerReceiver

@MainActor
final class ProductionDiagnostics {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.metricKitPayloads(sessions: sessions))
        try receiver.start()
    }
}
```

- **MetricKit alone captures.** Making the capability subscribes to `MXMetricManager`, and nothing
  else: no signal or exception handler is installed in the build that ships, so a crash SDK the
  app uses is undisturbed. The system writes a crash's `MXCrashDiagnostic` itself and delivers it
  in a diagnostic payload on a later launch (on the next one, from iOS 15 and macOS 12), with
  hangs, CPU and disk-write exceptions and slow launches; the day's metrics arrive about once a
  day. The payloads MetricKit still holds from before are kept as the capability is made.
- **Kept in the app, served during a session.** Each payload is kept once (the same kind and JSON
  delivered again adds nothing), the newest ten (`capacity:`), in the app's own Application
  Support directory (`directory:`), not the app group's, so a crash that arrives before anyone
  opens a session waits there across launches. The sidecar connects to
  `MetricKitPayloadsMirror.pluginID`; its `MetricKitPayloadsMirror.Snapshot` holds the open
  session's ID and every payload kept, the latest period first, each with its ID (the same in
  every session), kind (`.metrics` or `.diagnostics`, where a crash is in `crashDiagnostics`),
  period, arrival and JSON. While no session is open it holds none, and it empties as the session
  ends or expires. Within a session `MetricKitPayloadsMirror.Command.delete(id:)` and `deleteAll`
  delete the app's copies, such as once the sidecar has sent them on, and MetricKit delivering one
  again doesn't bring it back. Under a grant policy the payloads are served only to a session
  whose grant lists `MetricKitPayloadsMirror.pluginID`; a session whose grant doesn't is served its
  ID and no payloads.
- **Bounded.** A payload whose JSON is larger than a megabyte once redacted is dropped, so the
  snapshot holds at most a megabyte per payload of its capacity.
- **Redacted in the app.** MetricKit's payloads are the system's measurements: numbers,
  histograms, stack frames and system text. The one place the app's own data lands in them is an
  Objective-C exception's reason, so `MetricKitRedaction.standard` masks its `composedMessage` and
  `arguments`, at any depth, before the payload is kept anywhere, and keeps its `formatString`,
  the code's own text. `adding(keys:)` masks more of MetricKit's keys (matched exactly, as MetricKit
  spells them), and `.none` keeps payloads whole. A masked value becomes `"[REDACTED]"`.

**Push token and environment for test pushes.** To aim a test push at their own device, an
employee needs the device's APNs token, which APNs server it belongs to, and whether the app may
show notifications at all. The app can show a sidecar all three during its session. It is off
unless the app enables it. Link `DebugDrawerNotifications` (`.product(name:
"DebugDrawerNotifications", package: "DebugDrawer")`) beside the receiver, the UI-free half of the
Notifications plugin, make the mirror with the receiver's sessions, enable the capability, and hand
the mirror the token from the app delegate:

```swift
import DebugDrawerNotifications
import DebugDrawerReceiver
import Foundation

@MainActor
final class ProductionPush {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver
    let pushRegistration: PushRegistrationMirror

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        pushRegistration = PushRegistrationMirror(sessions: sessions)
        receiver.enable(.pushRegistration(pushRegistration))
        try receiver.start()
    }

    /// From application(_:didRegisterForRemoteNotificationsWithDeviceToken:).
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        pushRegistration.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }
}
```

- **What the sidecar sees.** It connects to `PushRegistrationMirror.pluginID`; the
  `PushRegistrationMirror.Snapshot` holds the open session's ID, the `registration`
  (`.registered(deviceToken:)` as lowercase hexadecimal, the form push tools take,
  `.failed(message:)` from `didFailToRegisterForRemoteNotifications(withError:)`, or
  `.notRegistered`), the `environment` (a `PushEnvironment`: the `server`, `.production` or
  `.sandbox`, and its `source`), and the `settings`: the authorization status (Allowed, Denied,
  Provisional, Not Asked) and each presentation setting, read from User Notifications as the session
  opens and again on `PushRegistrationMirror.Command.refresh`. The app can't fetch a token itself;
  only the delegate hears it, so the app registers for remote notifications as it does today and
  passes the token on.
- **The environment.** `PushEnvironment.detected()`, the default, reads the app's signature: on the
  Mac the `com.apple.developer.aps-environment` entitlement, elsewhere `aps-environment` in the
  embedded provisioning profile (`development` is the sandbox); an iOS app on a device with no
  profile is an App Store or TestFlight build, which is always production. A simulator build has
  neither, so it reads `nil`; pass `environment: PushEnvironment(server: .sandbox, source: .host)`
  where the app knows better.
- **The risk, and why a token may go over IPC.** The charter's rule "never expose secrets (keychain
  values, tokens) over IPC" means credentials. A device token isn't one: it names the device to
  APNs, and sending it a push also takes the company's APNs key or certificate, which neither the
  app nor the sidecar holds. It is still a device identifier, so the risk is low to medium, and the
  capability treats it as such: off by default, and served only during a session. Outside one the
  snapshot holds nothing; under a grant policy a session whose grant doesn't list
  `PushRegistrationMirror.pluginID` is served nothing either.
- **Where the token is written.** Nowhere but the capability's snapshot file in the app's own
  directory of the group's store, and only during a session: it is rewritten without the token as
  the session ends or expires, removed as a gate turns the capability off, and rewritten or removed
  as the receiver next starts after a launch killed during a session. The mirror keeps the token in
  memory; nothing goes to the defaults, another file, the audit log or a log line.

**Network mocks in production.** To reproduce a server's edge case on the build that ships (an
outage, an empty list, a slow or failing endpoint), a sidecar can answer some of the app's requests
with mock rules, for its session, on hosts the app allows. It is off unless the app enables it, and
it requires a grant (see "Signed grants" below). Link `DebugDrawerNetwork`
(`.product(name: "DebugDrawerNetwork", package: "DebugDrawer")`) beside the receiver, the UI-free
half of the Network plugin, which holds `NetworkMockRule` and `NetworkConditionProfile`; make the
model with the hosts a sidecar may mock, enable the capability, and list the capability's URL
protocol in each session whose requests may be mocked:

```swift
import CryptoKit
import DebugDrawerNetwork
import DebugDrawerReceiver
import Foundation

@MainActor
final class ProductionNetworkMocking {
    let sessions: DebugDrawerSessions
    let receiver: DebugDrawerReceiver
    let mocking: NetworkMocking
    let apiSession: URLSession

    init(grantServerKey: Curve25519.Signing.PublicKey, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        mocking = NetworkMocking(sessions: sessions, allowedHosts: [.exact("api.example.com"), .domain("staging.example.com")])
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.networkMocking(mocking))
        try receiver.start()

        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [NetworkMockingURLProtocol.self] + (configuration.protocolClasses ?? [])
        apiSession = URLSession(configuration: configuration)
    }
}
```

The sidecar, in a session whose grant lists `NetworkMocking.pluginID`, sends the rules:

```swift
// In the sidecar, once its session is open:
mocks.send(.setRules([NetworkMockRule(
    name: "Orders outage",
    matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/orders/**")),
    response: .init(status: 503, body: .text(#"{"error":"maintenance"}"#), contentType: "application/json")
)]))
```

- **Only the sessions the app configures.** Nothing is registered with URL loading and no method is
  replaced: `NetworkMockingURLProtocol` answers only for a `URLSession` whose configuration lists it,
  as above, and `URLSession.shared` and every other session are never touched. It claims only a
  request that a rule of the open session matches, over HTTP or HTTPS, to an allowed host, and
  declines the rest, which load as if it weren't listed. It never sends a request or reads a
  server's response, and an answer never enters the session's cache.
- **Only allowed hosts.** `allowedHosts` is the app's, fixed as it makes the model: `.exact(_:)`
  allows one host, and `.domain(_:)` the domain and every host under it (`.domain("example.com")`
  allows `api.example.com`, not `badexample.com`), ignoring case. A request to any other host is
  never answered, whatever a rule matches; with an empty list nothing is.
- **Only during a granted session.** The sidecar connects to `NetworkMocking.pluginID` with
  `NetworkMocking.Snapshot` (the open session's ID, the allowed hosts, its rules and profiles) and
  `NetworkMocking.Command`: `setRules(_:)` and `setConditions(_:)` replace the session's rules or
  profiles, and `reset` removes them. The capability requires a grant listing it even in a receiver
  without a grant policy, where its commands are refused as `commandRefused(.grantMissing)`; under a
  policy, a session whose grant doesn't list it is refused as `.capabilityNotGranted`. Each session
  starts with no rules, and as it ends, expires (from the expiry date, before the system's timer
  fires) or the receiver's or the capability's gate turns off, every request reaches the server
  again.
- **Rules as the plugin's, with two limits.** A rule matches and answers as in "Network mocks"
  above, the first that is on answering. A sidecar's rule may not use a regular expression or a
  file body: either is refused as `commandRefused(.malformedCommand)`, as no received expression is
  evaluated in the app and the sidecar can't place a file in its storage; use exact and wildcard
  patterns and a text body.
- **Conditioning shapes the answers.** A profile from `setConditions(_:)` (as in "Network
  conditions" above) delays a rule's answer by its latency, delivers its body no faster than its
  bandwidth, or fails it with its failure and rate. It applies only to the requests a rule answers:
  a request no rule matches goes to the server as it is, unslowed, as the app never sends one
  through the library.
- **The app shows it.** `mocking.snapshot.isActive` is `true` while a session is open with a rule on
  and a host allowed: show it with the session indicator, so the person holding the device knows
  the responses may not be the server's:

```swift
struct NetworkMockingIndicator: View {
    @ObservedObject var mocking: NetworkMocking

    var body: some View {
        if mocking.snapshot.isActive {
            Label("Network mocking active", systemImage: "exclamationmark.icloud")
        }
    }
}
```

**Switching environments in production.** To dogfood a production build against a staging or
canary backend, a sidecar can point the app at one of the backends the app allowlists, for its
session. It is off unless the app enables it, and it is high risk, so the allowlist is mandatory
and is all a sidecar can pick from. The app lists its environments, each an ID, a title and a
summary, and maps the ID to its own configuration in an adapter:

```swift
import CryptoKit
import DebugDrawerReceiver
import Foundation
import SwiftUI

@MainActor
final class BackendSwitcher: DebugDrawerEnvironmentAdapter {
    private(set) var baseURL = "https://api.example.com"

    func activate(_ environment: DebugDrawerEnvironment) {
        switch environment.id {
        case "staging": baseURL = "https://staging.api.example.com"
        case "canary": baseURL = "https://canary.api.example.com"
        default: baseURL = "https://api.example.com"
        }
    }
}

@MainActor
final class ProductionEnvironments {
    let sessions: DebugDrawerSessions
    let environments: DebugDrawerEnvironments
    let receiver: DebugDrawerReceiver

    init(grantServerKey: Curve25519.Signing.PublicKey, backend: BackendSwitcher, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        environments = DebugDrawerEnvironments(
            default: DebugDrawerEnvironment("production", title: "Production"),
            allowing: DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build"),
            DebugDrawerEnvironment("canary", title: "Canary"),
            adapter: backend
        )
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.environments(environments))
        try receiver.start()
    }
}

struct EnvironmentIndicator: View {
    @ObservedObject var environments: DebugDrawerEnvironments

    var body: some View {
        let snapshot = environments.snapshot
        if snapshot.isSwitched, let active = snapshot.environments.first(where: { $0.id == snapshot.activeEnvironment }) {
            Label("Backend: \(active.title)", systemImage: "server.rack")
        }
    }
}
```

- **The risk: high.** Whoever holds the sidecar, a leaked copy included, can send the app's
  traffic, the signed-in account's credentials with it, to another backend. Only a backend the app
  lists can be chosen, so the worst a leak does is point the app at your own staging.
- **The allowlist is mandatory and holds no URL.** `DebugDrawerEnvironments` and
  `.environments(default:allowing:_:adapter:)` take the default and at least one allowed
  environment as separate parameters, so an empty allowlist doesn't compile; an allowed
  environment repeating another's ID (the default's included) traps, as does an empty ID. Write the
  list in the app's source, not from remote configuration, which a leak would target next. A
  `DebugDrawerEnvironment` has an ID, a title and a summary and nothing else: base URLs, hosts and
  keys stay in the adapter, and no command or snapshot has a field an address could travel in.
- **Only by ID, only listed ones.** The sidecar connects to `DebugDrawerEnvironments.pluginID` with
  `DebugDrawerEnvironments.Snapshot` (the environments, the default's ID and the active one's) and
  `DebugDrawerEnvironments.Command`: `activate(environment:)`, with an ID, and `reset`. An ID the
  app didn't list (an address among them) is refused as `commandRefused(.notExposed)` and changes
  nothing; the adapter is handed the app's own `DebugDrawerEnvironment`, never one decoded from the
  sidecar. Until the app enables `.environments(_:)`, a switch is refused as
  `commandRefused(.unknownCapability)`, even inside a session.
- **A grant when a verifier is configured.** With a `DebugDrawerGrantPolicy` on the sessions, as
  above, a switch needs a session whose grant lists `DebugDrawerEnvironments.pluginID`: without a
  grant no session opens, and a grant for other capabilities is refused as
  `commandRefused(.capabilityNotGranted)`. Grants stay optional (without a policy a switch needs
  only a session); add `.requiringGrant()` to the capability to refuse switches as
  `commandRefused(.grantMissing)` in any session without one.
- **For the session, always.** As the session ends, expires or the receiver's or the capability's
  gate turns off, the adapter is told to activate the default, audited as `changeReverted`. The
  environment a session switched to is recorded in the defaults before the adapter is told, so
  when the app is killed during a session the next launch activates the default as it makes the
  capability: make it as the app starts, before the first request, and keep the switch itself in
  memory in the adapter.
- **The app shows it.** `environments.snapshot.isSwitched` is `true` while the app is pointed
  anywhere but its default, which is only ever during a session: show the backend in the session
  indicator, as `EnvironmentIndicator` does, so the person holding the device knows their traffic
  isn't going to production.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.environments` lists the environments under a
high-risk warning, the active one marked, with Switch for each other one and Reset to Default.

**Location spoofing in production.** To test geo features (a store finder, a delivery zone, a
regional price) on the build that ships, a sidecar can replace the locations the app reads with a
coordinate of its own, for its session. Many apps forbid this for fraud or compliance reasons, so
it is off unless the app enables it, nothing is intercepted, and the app is told as spoofing starts
and ends, so its own fraud checks can react. Link `DebugDrawerLocation` (`.product(name:
"DebugDrawerLocation", package: "DebugDrawer")`) beside the receiver, pass the readings a tester
should be able to move through the model, and enable the capability:

```swift
import CoreLocation
import CryptoKit
import DebugDrawerLocation
import DebugDrawerReceiver
import Foundation
import SwiftUI

/// What the app knows of where the device is: the location its features use, and whether it is
/// spoofed, which the app's own fraud checks read.
@MainActor
final class LocationSignals: ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isSpoofed = false

    /// Told by `LocationSpoofing` as a spoof starts, moves and ends.
    func spoofingDidChange(_ spoofed: CLLocation?) {
        isSpoofed = spoofed != nil
        // At the end, drop the spoofed location until Core Location delivers a real one.
        location = spoofed
    }

    func update(_ location: CLLocation?) {
        self.location = location
    }
}

@MainActor
final class ProductionLocation {
    let sessions: DebugDrawerSessions
    let signals: LocationSignals
    let spoofing: LocationSpoofing
    let receiver: DebugDrawerReceiver

    init(grantServerKey: Curve25519.Signing.PublicKey, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        let signals = LocationSignals()
        self.signals = signals
        spoofing = LocationSpoofing(sessions: sessions, spoofingDidChange: signals.spoofingDidChange)
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.locationSpoofing(spoofing))
        try receiver.start()
    }

    /// From the app's CLLocationManagerDelegate, locationManager(_:didUpdateLocations:).
    func didUpdateLocations(_ locations: [CLLocation]) {
        signals.update(spoofing.locations(replacing: locations).last)
    }
}

struct LocationSpoofingIndicator: View {
    @ObservedObject var spoofing: LocationSpoofing

    var body: some View {
        if let coordinate = spoofing.snapshot.coordinate {
            Label("Location spoofed: \(coordinate.latitude), \(coordinate.longitude)", systemImage: "location.slash")
        }
    }
}
```

- **The risk: high.** Whoever holds the sidecar, a leaked copy included, can make the app believe
  the device is anywhere, which is what location fraud does: claim a region's offer, check in
  somewhere they aren't, appear inside a delivery zone.
- **Nothing intercepted: only what the app passes through.** A release build replaces no method
  and swaps no delegate. Only the readings the app passes through
  `spoofing.location(replacing:)` or `spoofing.locations(replacing:)` are spoofed, so route the
  ones a tester should be able to move and leave the ones your fraud checks rely on on Core
  Location's own. Both are safe from any thread, and so are `spoofing.isSpoofing` and
  `spoofing.spoofedLocation`; a spoofed reading is dated when it is read.
- **The app is told.** `spoofingDidChange`, which the model requires, is called on the main actor
  with the spoofed location as a spoof lands or moves, and with `nil` as it ends, whatever ends it;
  `spoofing.snapshot.isSpoofing` and `spoofing.isSpoofing` say the same. Raise your own fraud signal
  from it (`LocationSignals.isSpoofed` above), and treat what the app read meanwhile as not the
  device's.
- **A coordinate, only.** The sidecar connects to `LocationSpoofing.pluginID` with
  `LocationSpoofing.Snapshot` (the spoofed `coordinate`, or `nil`) and `LocationSpoofing.Command`:
  `spoof(_:)`, with a `LocationCoordinate`, and `stop`. A coordinate off the Earth (latitude beyond
  ±90, longitude beyond ±180, or not a number) is refused as `commandRefused(.malformedCommand)`.
  Until the app enables `.locationSpoofing(_:)`, a spoof is refused as
  `commandRefused(.unknownCapability)`, even inside a session; outside a session it is refused
  (`noActiveSession`), and a spoof the model is handed directly outside one is ignored.
- **A grant when a verifier is configured.** With a `DebugDrawerGrantPolicy` on the sessions, as
  above, a spoof needs a session whose grant lists `LocationSpoofing.pluginID`: without a grant no
  session opens, and a grant for other capabilities is refused as
  `commandRefused(.capabilityNotGranted)`. Grants stay optional (without a policy a spoof needs only
  a session); add `.requiringGrant()` to the capability to refuse spoofs as
  `commandRefused(.grantMissing)` in any session without one.
- **For the session, always.** As the session ends, expires or the receiver's or the capability's
  gate turns off, the readings are real again, the app is told `nil`, and the end is audited as
  `changeReverted`; the readings stop being spoofed at the session's expiry date even before the
  sessions' timer fires in an app that was suspended. The coordinate is kept in memory only, so a
  kill ends the spoof with the process; a flag (never the coordinate) kept in the defaults while
  spoofing lets the next launch tell the app `nil` as it makes the capability, so a location the
  app kept from that launch can be dropped. Make it as the app starts.
- **The app shows it.** Show the spoofed location in the session indicator, as
  `LocationSpoofingIndicator` does, so the person holding the device knows the app isn't using
  where they are.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.locationSpoofing` shows the spoofed location
under a high-risk warning, with latitude and longitude fields, a few places to pick, and Stop
Spoofing.

**Allowlisted UserDefaults in production.** To try a production build with a setting changed
(another plan, tips turned on, a longer page), a sidecar can read and edit the UserDefaults keys
the app allowlists, and no other. It is off unless the app enables it, and enabled with no key it
lists nothing. The app declares each key with the kind of value it holds:

```swift
import Combine
import DebugDrawerReceiver
import Foundation
import os
import SwiftUI

@MainActor
final class ProductionDefaults {
    private static let logger = Logger(subsystem: "com.example.MyApp", category: "Sidecar")
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver
    private var auditForwarding: AnyCancellable?

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.userDefaults(
            .choice("plan", title: "Plan", options: ["free", "pro"]),
            .bool("showsTips", title: "Shows Tips"),
            .integer("itemsPerPage", title: "Items per Page", in: 10 ... 100)
        ))
        auditForwarding = sessions.auditEntries.sink { entry in
            for change in entry.changes ?? [] {
                Self.logger.notice("Sidecar changed \(change.key, privacy: .public)")
            }
        }
        try receiver.start()
    }
}

struct TipsBanner: View {
    @AppStorage("showsTips") private var showsTips = false

    var body: some View {
        if showsTips {
            Text("Tip: drag a row to reorder it.")
        }
    }
}
```

- **The risk: medium.** Whoever holds the sidecar can change any allowlisted value, and with it
  whatever the app derives from that value. They can't read or write any other key: the domain is
  never listed, and a key the app didn't allowlist is refused as `commandRefused(.notExposed)` and
  stays as it was.
- **Each key with its kind.** `DebugDrawerUserDefaultsKey` declares a key as `.string(_:title:maximumLength:)`,
  `.integer(_:title:in:)`, `.double(_:title:in:)`, `.bool(_:title:)` or `.choice(_:title:options:)`
  (stored as a string). A key reads as its kind only (data or a date stored under a string key
  reads as none), and a value of another kind, out of the key's bounds, longer than its maximum
  or not one of its options is refused as `commandRefused(.malformedCommand)`. A key listed twice,
  an empty one, one of DebugDrawer's own (prefixed `DebugDrawer.` or `com.debugdrawer.`), a
  choice without options and a bound that isn't finite trap. Write the allowlist in the app's
  source.
- **Never allowlist a secret.** A key's value is shown to the sidecar and written to the audit log
  with each edit, so no tokens, passwords or identifiers of a person.
- **What a sidecar sends.** It connects to `DebugDrawerUserDefaults.pluginID` with
  `DebugDrawerUserDefaults.Snapshot` (each key's declaration and value, and the keys it edited) and
  `DebugDrawerUserDefaults.Command`: `set(key:value:)` with a `DebugDrawerUserDefaultsValue`
  (`.string`, `.integer`, `.double`, `.bool`), `remove(key:)`, which leaves the app reading its
  registered default, and `revertAll`. Until the app enables `.userDefaults(...)`, or while it
  is disabled or its gate is off, every one of them is refused, even inside a session.
- **Every edit in the audit log.** Each edit is audited as `commandApplied` with the key and its
  value before and after in the entry's `changes` (`DebugDrawerAuditEntry.Change`: `key`,
  `oldValue`, `newValue`, `nil` for a key holding no value of its kind), and the session's revert
  as `changeReverted` with what it put back, so a host forwarding the log, as `ProductionDefaults`
  does, keeps what the sidecar changed. Entries of other capabilities have no `changes`, and the
  JSON leaves it out.
- **For the session, unless the app says otherwise.** Before a key's first edit the model records
  what the key held, in the same defaults (`DebugDrawer.UserDefaults.originalValues`). As the
  session ends, expires or a gate turns off, each edited key is put back exactly as it was,
  removed if it held only its registered default; edits a session left when the app was killed
  are put back as the next launch makes the capability, so make it at startup, before the app
  reads the keys. `scope: .persistent` keeps the edits until a sidecar sends `revertAll`.
  `DebugDrawerUserDefaults(_:defaults:)` (pass it to `.userDefaults(_:scope:)`) reads the keys
  of another suite, and follows the app's own writes through UserDefaults' change notification.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.userDefaults` lists the keys with their
values, an editor for each kind (a text field, a number field, a switch or a picker), Remove, and
Revert All while any key is edited.

**Hangs and signposts in production.** A hang a dogfooder hits on an optimized build can reach the
team with the stack it was stuck on, and the app's own timings beside it: during a sidecar's
session the app records the main thread's hitches and hangs, using the Hangs plugin's monitor, and
the intervals the app marks, as `os_signpost` marks them. It is off unless the app enables it.
Link `DebugDrawerHangDetector` (`.product(name: "DebugDrawerHangDetector", package:
"DebugDrawer")`) beside the receiver, the UI-free half of the Hangs plugin, make the recorder with
the receiver's sessions, enable the capability, and mark the intervals worth timing:

```swift
import DebugDrawerHangDetector
import DebugDrawerReceiver
import Foundation

@MainActor
final class ProductionPerformance {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let traces: PerformanceTraces
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        traces = PerformanceTraces(sessions: sessions)
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.performanceTraces(traces))
        try receiver.start()
    }

    func loadFeed(from url: URL) async throws -> Data {
        let interval = traces.beginInterval("Load feed")
        defer { traces.endInterval(interval) }
        return try await URLSession.shared.data(from: url).0
    }
}
```

- **The risk: low.** Whoever holds the sidecar sees stack traces and timings of the app's own
  code. No user data is recorded (an interval's name is a `StaticString`, a literal in the app's
  code), and nothing the sidecar sends is executed.
- **Off until a sidecar records.** Until the app enables `.performanceTraces(_:)`, a command is
  refused as `commandRefused(.unknownCapability)`. Enabled, nothing runs until a sidecar sends
  `PerformanceTraces.Command.start` in an open session: no run loop observer, no watcher thread, no
  interval kept, and `beginInterval(_:)` returns one that records nothing. A session opened for
  something else starts nothing either.
- **What it records.** Each stall of the main thread at least `hitchThreshold` long (100 ms unless
  the app picks another) is a `Stall`: `.hitch`, or `.hang` from `hangThreshold` (250 ms), with
  when it began, how long it lasted, and the main thread's frames, sampled once it reached the
  hitch threshold. Each interval that begins and ends while recording is a `SignpostInterval` with
  its name, start and duration. The newest 50 stalls and 500 intervals are kept (`limits:`); the
  snapshot counts what the bounds dropped.
- **Stacks from an optimized build.** A frame carries its address, its image's file name, the
  image's UUID (`LC_UUID`) and the address's offset into the image, plus the nearest symbol the
  image exports. A stripped App Store build exports few of its own, so the sidecar shows the app's
  frames as `MyApp + 0x1c1f0` and the system's by name; the report's `performance.txt` ends with
  the binary images, each with its load address and UUID, so `atos -o MyApp.app.dSYM -l <load
  address> <address>` names the app's frames with the dSYM archived for that build.
- **For the session, always.** As the sidecar sends `stop`, as the session ends or expires, and as
  the receiver's or the capability's gate turns off, the observer is removed, the watcher thread
  ends, and the recording is deleted (audited as `changeReverted`). It lives only in memory and in
  the capability's snapshot file in the app's own directory of the store; a file a killed launch
  left behind is removed as the next launch enables the capability, so enable it at startup. A
  sidecar's export is its own copy, in its report (`Command.export` records it).
- **What recording costs.** Measured in an optimized build on an Apple M1 Ultra by
  `PerformanceTracesOverheadTests` (`just test-release`), with the default thresholds: about 0.6 µs
  added to each turn of the main run loop (about 0.13 µs a checkpoint); a watcher wake 40 times a
  second at about 0.08 µs of work each, about 3 µs of CPU a second; for each stall, a few µs with
  the main thread stopped while its stack is read, then about 15 µs a frame on the main actor to
  name its frames (at most 128); and about 0.45 µs to begin and end a signpost interval, 0.06 µs
  while nothing records.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.performanceTraces` offers Start Recording, then
lists the stalls, newest first, each open to its main-thread stack, and the intervals, with Stop
and Delete; Create Report adds `performance.txt`.

**The app's state in every report.** To know which build and configuration a report came from,
a sidecar can read a snapshot of the app's state during its session and attach it to every report:
the version, build, commit, branch and CI build always, and only what the app registers beside
them, its flag and experiment overrides, experiment buckets, environment, a hashed user ID and
values of its own. It is off unless the app enables it. Link `DebugDrawerAppInfo` (`.product(name:
"DebugDrawerAppInfo", package: "DebugDrawer")`) beside the receiver, the UI-free half of the App
Info plugin, make the snapshot's model with the receiver's sessions and the sources to show, and
enable the capability:

```swift
import DebugDrawerAppInfo
import DebugDrawerReceiver
import Foundation

@MainActor
final class Account {
    var userID: String?
    var plan = "free"
}

@MainActor
final class ProductionAppStateSnapshot {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let appState: DebugDrawerAppState
    let receiver: DebugDrawerReceiver

    init(flags: DebugDrawerFeatureFlagOverrides, account: Account, container: URL) throws {
        appState = DebugDrawerAppState(
            sessions: sessions,
            featureFlags: flags,
            userID: { account.userID },
            values: [DebugDrawerAppStateField("plan") { .string(account.plan) }]
        )
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        receiver.enable(.appState(appState))
        try receiver.start()
    }
}
```

- **The risk: low.** Whoever holds the sidecar learns which build the app is and how it is
  configured, and, when the app registers one, a hashed identifier of the signed-in user. Raw user
  IDs, tokens and keychain values are never read by the capability, and nothing the sidecar sends
  is executed: its one command, `DebugDrawerAppState.Command.refresh`, reads the state again.
- **Every field beyond the build is the app's choice.** With nothing registered, the
  `DebugDrawerAppState.State` holds only `bundleIdentifier`, `version`, `build`, `buildMetadata`
  (`AppInfoBuildMetadata`: the commit, branch and CI build the app passes, or its Info.plist's
  `DebugDrawerGitCommit`, `DebugDrawerGitBranch` and `DebugDrawerCIBuildNumber`, as App Info reads
  them) and `date`. Pass `featureFlags:` (a `DebugDrawerFeatureFlagOverrides`) for the flags a
  sidecar overrides now, `experiments:` (a `DebugDrawerExperimentOverrides`) for every listed
  experiment's bucket and whether it is forced, `environments:` (a `DebugDrawerEnvironments`) for
  the active backend, `userID:` for the hashed user ID, and `values:` for the app's own: each a
  `DebugDrawerAppStateField`, a key and a closure returning a string, a number or a Boolean
  (`DebugDrawerAppStateValue`). The models are the capabilities' own, read as the state is read and
  followed during a session, so an override a sidecar sets shows at once; hand the same model to the
  receiver, as `.featureFlagOverrides(flags)` does above.
- **Never register a secret.** What a field's closure returns leaves the app. Keys aren't checked
  for what they look like (a key named `plan` can still be handed a token), so the app decides:
  no tokens, passwords, keychain values or raw identifiers of a person. The sidecar's report masks
  values under the keys its `DebugDrawerRedaction` masks, as a second line, not the first.
- **The user ID is hashed in the app.** The closure's raw ID is hashed as it is read, before
  anything holds it, with HMAC-SHA256 under 32 random bytes the install makes on its first hash and
  keeps in the app's own defaults (`DebugDrawer.AppState.userIDKey`, which Reset App State keeps),
  never the app group's. The same user reads the same on every launch of the install, so one
  install's reports correlate, while a sidecar or a report can't test a guessed ID against the hash
  without the key, which never leaves the app; another install hashes the same user differently.
  Return `nil` while no one is signed in.
- **Served during a session only.** Outside one the snapshot holds nothing and no closure is asked;
  under a grant policy a session whose grant doesn't list `DebugDrawerAppState.pluginID` is served
  nothing. The state lives in memory and in the capability's snapshot file in the app's own
  directory of the store, rewritten without it as the session ends. Until the app enables
  `.appState(_:)`, a refresh is refused as `commandRefused(.unknownCapability)`.
- **In bug reports too.** `appState.read()` reads the state at any time, so the app's bug reports
  carry it: `DebugDrawerBugReports(sessions: sessions) { appState.read() }`.

In the sidecar, the kit's `DebugDrawerSidecarPlugin.appState` shows the build and each registered
field with Refresh. `DebugDrawerSidecarView` hosts it as soon as the app is reached, so Create
Report adds `App State/app-state.json` to every report, opened or not.

In a debug build the receiver runs beside the drawer: show the same model in a plugin through
`DebugDrawerPluginTransport.direct(to:)`, and pass it to `.featureFlagOverrides(_:)` or
`.model(_:id:scope:)`, so what a sidecar does is seen in the app's own drawer. `DebugDrawer`
re-exports the receiver's module. Keep the receiver's store directory apart from a debug
`DebugDrawerAppGroupStoreServer`'s, as both perform the commands left there.

### Signed grants: who may open a session

Team signing and a shared app group keep other companies' apps out, but not a sidecar build that
reached the wrong person, and a macOS group container is weaker than an iOS one. Grants are an
optional layer on top: the sidecar signs the employee in (with the company's SSO, which the
sidecar implements) and gets a short-lived grant from the company's server, listing the
capabilities that person may drive and when it expires; the app verifies it with a public key it
embeds. Without a grant policy, sessions work exactly as above.

```swift
import CryptoKit
import DebugDrawerReceiver

@MainActor
final class GrantedProductionReceiver {
    let sessions: DebugDrawerSessions
    let receiver: DebugDrawerReceiver

    init(flags: FlagServiceAdapter, grantServerKey: Curve25519.Signing.PublicKey, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        try receiver.start()
    }
}
```

The sidecar sends the grant once, as it opens the session:

```swift
// In the sidecar, once the employee signed in and the company's server issued a grant:
sessionControl.send(.open(duration: 15 * 60, grant: grantFromServer))
```

With a policy, the sessions are default-deny:

- **A session needs a valid grant.** Opening one without a grant is refused as
  `commandRefused(.grantMissing)`; with one the verifier rejects (malformed, or not signed by a
  trusted key as it is) as `.grantInvalid`; with one issued for another app (its `aud` lacks the
  policy's `audience`) as `.grantWrongAudience`; before its `nbf` as `.grantNotYetValid`; at or
  after its `exp` as `.grantExpired`; and with one that already opened a session as
  `.grantReplayed`. Each refusal is audited, and every command after it is refused as
  `.noActiveSession`.
- **The grant bounds the session.** A session expires at its `exp` at the latest, whatever
  duration the sidecar asked for, and a command in it to a capability the grant doesn't list is
  refused as `.capabilityNotGranted`. `session.grant` holds the grant (`id`, `subject`,
  `audiences`, `capabilities`, `notBefore`, `expires`), so the app's indicator can show who holds
  it.
- **Clock skew.** A grant is accepted up to `clockSkewTolerance` seconds (a minute by default)
  before its `nbf`, for a server whose clock runs ahead of the device's; `exp` is never extended.
- **One session per grant.** The app remembers the grant IDs it accepted until each expires, in
  memory: after a relaunch a grant copied from the store could open one more session before it
  expires, so issue grants that last minutes, not days.
- **Nothing secret is kept.** The token and its signature are read once and never written to a
  snapshot or the audit log; `sessionOpened(expires:grant:)` names the grant by its `id` and
  `subject` alone.
- **High-risk capabilities.** `.requiringGrant()` on a capability
  (`receiver.enable(.model(environments, id: "MyApp.Environment", scope: .session(revertWith: .reset)).requiringGrant())`)
  refuses its commands as `.grantMissing` in a session without a grant, so it works only in an
  app that configures grants.

**The grant format.** A grant is a JSON Web Token (RFC 7519) in JWS compact serialization (RFC
7515), so a server issues one with any JWT library: three base64url segments without padding,
each the canonical encoding of its bytes, joined by `.`.

- **Header:** `{"alg":"EdDSA","typ":"debugdrawer-grant+jwt"}` for an Ed25519 key (RFC 8037),
  or `{"alg":"ES256","typ":"debugdrawer-grant+jwt"}` for a P-256 key. `typ` must be exactly
  that, so no other token the key signs passes as a grant; a header with `crit` is refused. The
  app trusts the keys it lists, each for its own algorithm (`.ed25519(_:)`, `.p256(_:)`); list
  two while the server rotates its key.
- **Claims:** `jti` (the grant's unique ID, a non-empty string), `sub` (who holds it), `aud`
  (the app's bundle identifier, as a string or an array of them), `nbf` and `exp` (seconds since
  1970, numbers), and `capabilities` (an array of the capability IDs it allows, such as
  `"DebugDrawer.FeatureFlagOverrides"`). Other claims are ignored.
- **Signature:** over the ASCII bytes of `<header segment>.<claims segment>`: Ed25519's 64-byte
  signature, or ES256's 64-byte `r` and `s` (ECDSA over SHA-256). It is checked before the claims
  are read, and a token over 8,192 bytes isn't read at all.

A test signer, which the repository's tests sign every grant with, shows each step:

```swift
import CryptoKit
import DebugDrawerReceiver
import Foundation

/// Signs grants in DebugDrawer's format with an Ed25519 key: for tests, and as a reference for
/// the server that issues them.
struct DebugDrawerTestGrantSigner {
    let key: Curve25519.Signing.PrivateKey

    func token(for grant: DebugDrawerGrant) throws -> String {
        struct Claims: Encodable {
            let jti: String
            let sub: String
            let aud: [String]
            let nbf: Int
            let exp: Int
            let capabilities: [String]
        }
        let header = Data(#"{"alg":"EdDSA","typ":"debugdrawer-grant+jwt"}"#.utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let claims = try encoder.encode(Claims(
            jti: grant.id, sub: grant.subject, aud: grant.audiences,
            nbf: Int(grant.notBefore.timeIntervalSince1970), exp: Int(grant.expires.timeIntervalSince1970),
            capabilities: grant.capabilities
        ))
        let signingInput = "\(base64URL(header)).\(base64URL(claims))"
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature))"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

For example, the test signer with RFC 8037's Ed25519 key (public key
`11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo` in base64url) issued this grant for
`DebugDrawer.FeatureFlagOverrides` to `jane@example.com`, for `com.example.MyApp`, from
1778307200 to 1778308100; its claims segment decodes to
`{"aud":["com.example.MyApp"],"capabilities":["DebugDrawer.FeatureFlagOverrides"],"exp":1778308100,"jti":"grant-0001","nbf":1778307200,"sub":"jane@example.com"}`:

```
eyJhbGciOiJFZERTQSIsInR5cCI6ImRlYnVnZHJhd2VyLWdyYW50K2p3dCJ9.eyJhdWQiOlsiY29tLmV4YW1wbGUuTXlBcHAiXSwiY2FwYWJpbGl0aWVzIjpbIkRlYnVnRHJhd2VyLkZlYXR1cmVGbGFnT3ZlcnJpZGVzIl0sImV4cCI6MTc3ODMwODEwMCwianRpIjoiZ3JhbnQtMDAwMSIsIm5iZiI6MTc3ODMwNzIwMCwic3ViIjoiamFuZUBleGFtcGxlLmNvbSJ9.Cc_FvvFlgJZkYRx3JqfE6EtZY4A8GF30qbGB5gLa51q7PN3a52hwmmLAYLBURiZrQ1NuoCFJUp_c89PJC5bFCA
```

Ed25519 in CryptoKit randomizes its signatures, so signing the same claims again gives another
signature that verifies just as well. Keep the private key on the server; the app holds only the
public key. To bring another format (a token your SSO already issues, say), conform to
`DebugDrawerGrantVerifier`: check the signature and return a `DebugDrawerGrant`, and the sessions
check the audience, validity window, single use and capabilities as above.

### Sidecar sessions in the background: keeping the app reachable

On iPhone the sidecar and the app take turns in the foreground, and a backgrounded app is
suspended within seconds, so it stops answering on the socket. A `DebugDrawerBackgroundKeeper`
keeps it running while a session is open, through only what each platform sanctions for that, and
lets go as the session ends:

```swift
@MainActor
final class SidecarBackground {
    let keeper: DebugDrawerBackgroundKeeper

    init(sessions: DebugDrawerSessions, socketServer: DebugDrawerSocketServer) {
        keeper = DebugDrawerBackgroundKeeper(sessions: sessions, socketServer: socketServer)
    }

    /// From a Start Debug Session button, before switching to the sidecar.
    func startDebugSession() {
        keeper.startSession(duration: 10 * 60, title: "Debug session", subtitle: "Inspector is connected")
    }
}
```

While a session is open the keeper holds the platform's short request, whoever opened the
session. `startSession(duration:title:subtitle:)` is for a person's action in the app: it opens a
session (or uses the open one) and, on iOS and iPadOS 26 and later, submits a
`BGContinuedProcessingTask`, which the system shows with the session's progress and a way to stop
it. Its identifier is `continuedProcessingIdentifierPrefix` (by default the bundle identifier and
`.DebugDrawerSession`) plus the session's ID, so list the prefix with a wildcard in the Info.plist
of each configuration that makes a keeper (the debug one for the drawer, and the release one too
when the app's receiver makes one, as below); no `UIBackgroundModes` entry is needed:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER).DebugDrawerSession.*</string>
</array>
```

Every request ends as the session ends or expires. The session ends when the last sidecar
disconnects from the socket (not when the app stops its own server), when the person stops the
continued processing task in the system's progress, or when the system expires that task, so
nothing keeps the app running for a sidecar that is gone, and the session's changes revert.
`keeper.request` publishes what is held (`DebugDrawerBackgroundRequest`: `none`, `backgroundTask`,
`continuedProcessing`, `activity`), to show beside the session indicator.

| Platform | What the keeper holds | Limits |
|---|---|---|
| iOS, iPadOS 26 and later | From `startSession`: a `BGContinuedProcessingTask`, with the system's progress UI; otherwise a UIKit background task | The task must be submitted from a person's action while the app is in the foreground, and runs at once or not at all (`.fail`): when the system refuses it, the session keeps the background task. The system may end it at any time (the person stopping it, resources, a task that looks stalled): its progress is the session's elapsed time, reported at each command the sidecar sends, so an idle sidecar may see it expire. The Simulator refuses it ("BGTaskScheduler is not available on this platform"), so check it on a device. |
| iOS, iPadOS before 26; tvOS; visionOS | A UIKit background task (`beginBackgroundTask(withName:expirationHandler:)`) | About 30 seconds once the app is in the background, a handoff rather than a session; no system indicator, so the app's own session indicator is the one shown. When it expires the keeper holds nothing until the app returns to the foreground, then asks again. |
| macOS, Mac Catalyst | A `ProcessInfo` activity (`.userInitiatedAllowingIdleSystemSleep`) | Apps aren't suspended there; the activity keeps App Nap from slowing the app, and lets the Mac sleep when idle. It doesn't expire; no system indicator. |
| watchOS | Nothing | `WKExtendedRuntimeSession` runs only for its own session types (self care, mindfulness, physical therapy, smart alarm), none of which a debug session is, so a backgrounded watch app is suspended as usual. |

The keeper never claims an audio, location or VoIP background mode. It is part of
`DebugDrawerReceiver`, like the sessions, and works in every build: a release build that links the
receiver makes it with `DebugDrawerBackgroundKeeper(sessions: receiver.sessions)` (there is no
socket server to pass), and it holds a request only while a session is open, which the receiver
allows only for the capabilities the host enables.

### Building a sidecar app with the kit

`DebugDrawerSidecarKit` is the sidecar app, as a library: a company builds its own app from it,
under its own name, signing and app group, rather than installing one DebugDrawer ships. One view
is the whole app:

```swift
import DebugDrawerSidecarKit
import SwiftUI

@main
struct CompanySidecar: App {
    var body: some Scene {
        WindowGroup {
            DebugDrawerSidecarView(groupIdentifier: "group.com.example.debug")
        }
    }
}
```

The sidecar app and the apps it reaches list the same group in their
`com.apple.security.application-groups` entitlement and keep their store in its `DebugDrawer`
folder (`DebugDrawerAppGroupContainer.storeDirectory`). The view's sidebar lists every app there
that serves a sidecar: a release build running `DebugDrawerReceiver`, or a debug build running
`DebugDrawerAppGroupStoreServer`, each with its name, version, build and bundle ID. Each registers
itself with a presence file in its own directory of the store (`<store>/apps/<bundle
ID>/presence.json`: its bundle ID, name, version, build, the capabilities it serves and the
protocol version it speaks, `DebugDrawerSidecarApp.protocolVersion`) as it starts, rewrites it as
the capabilities it serves change and as it comes to the foreground, and removes it as it stops;
the list watches the store's `apps` folder and each app's folder and changes as the files do, with
no polling. An app that was killed stays listed, with when it was last seen. An app whose host has
turned its receiver off (`DebugDrawerReceiver.isAllowed`) stays listed as turned off, serving
nothing.

**Several apps, one sidecar.** A company with several apps gives them one employee tool: each app
of the group serves its own directory of the store, `apps/<bundle ID>/`, holding its presence
file, its socket, its snapshots (the sessions' among them) and the commands for it, and the
sidecar lists them all and scopes every connection, session and file to the app picked. The
directory comes from the app's main bundle, never from a parameter, so one app's receiver or store
server never performs another's commands, never serves where another's sidecar reads, and refuses
a command naming a capability only another app serves (`commandRefused(.unknownCapability)`).
That is as far as the library can keep apps apart: **the system doesn't isolate apps within one
app group**, and any app of the group can read the whole container, another app's captured logs
and requests included. For real isolation, give each app an app group of its own and have the
sidecar join every one:

```swift
DebugDrawerSidecarView(groupIdentifiers: ["group.com.example.shop.debug", "group.com.example.wallet.debug"])
```

`DebugDrawerSidecarAppList(groupIdentifiers:)` and `init(storeDirectories:)` list several groups'
apps the same way; an app found in two groups is listed once, as it last registered, and a group
the system gives no container is reported in `error` while the others are still listed.
Encrypting each app's files wouldn't help: a key both the app and the sidecar can reach sits in
the same container. A store from before per-app directories (files at the top of `DebugDrawer/`)
is neither read nor removed; each app writes its own directory as it next starts serving.

Picking an app connects to it with `DebugDrawerSidecarTransport`: live over its socket while it
answers, through the store while it is suspended. For an app whose commands need a session (it
serves `DebugDrawer.Sessions`), the detail shows the session's state with Open Session and End
Session. When its sessions require a signed grant, pass `grant`, which fetches one from the
company's server for the app picked; what it throws is shown, and no session opens:

```swift
DebugDrawerSidecarView(groupIdentifier: "group.com.example.debug", sessionDuration: 10 * 60) { app in
    try await GrantService.shared.grant(for: app.bundleIdentifier)
}
```

Below it, a picker shows the plugins the app serves, drawn by the plugins' own views over the
transport: `.console` and `.network` by default (a debug build's), and a plugin for every
capability the receiver ships, each named for its capability, which a sidecar for production
builds lists:

```swift
DebugDrawerSidecarView(
    groupIdentifier: "group.com.example.debug",
    plugins: [
        .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview,
        .accessibilityEnvironmentOverrides, .analyticsEvents, .metricKitPayloads, .networkMocking,
        .diagnosticsCapture, .bugReports, .pushRegistration, .scenarios, .authActions, .appStateReset,
        .environments, .locationSpoofing, .userDefaults, .performanceTraces, .appState
    ]
)
```

The view shows only those the app picked serves, so listing every one costs nothing for an app
that enables a few.

| Plugin | Capability | What the sidecar shows and sends |
|---|---|---|
| `.featureFlagOverrides` (Flags) | `.featureFlagOverrides` | Each flag with a switch, or a field and Set for a number or a string (only a value of the flag's kind), Clear, Clear All Overrides |
| `.experimentOverrides` (Experiments) | `.experimentOverrides` | Each experiment with a picker of its variants, which are forced and so excluded from analytics, Clear, Clear All Overrides |
| `.logLevels` (Log Levels) | `.logLevels` | Each subsystem with a picker of its levels, which are raised, Reset, Reset All Levels |
| `.tweaks` (Tweaks) | `.tweaks` | Each production-safe tweak with the control it declares (switch, picker, field and Set, stepper), Reset, Reset All |
| `.localizationReview` (Strings) | `.localizationReview` | The review mode: standard, pseudo-localized or keys |
| `.accessibilityEnvironmentOverrides` (Accessibility) | `.accessibilityEnvironmentOverrides` | Dynamic Type, Increase Contrast and Reduce Motion, each the system's or overridden, Reset |
| `.analyticsEvents` (Analytics) | `.analyticsEvents` | The session's events, newest first, with their properties as the app redacted them, Clear |
| `.metricKitPayloads` (MetricKit) | `.metricKitPayloads` | The payloads the app keeps, crash diagnostics among them, each with Copy JSON and Delete, Delete All; Create Report adds each as JSON |
| `.networkMocking` (Mocking) | `.networkMocking` | The hosts the app allows, the session's rules and delays with a switch and Remove, a form for a new rule (host, method, path, status, body) and one for a delay, Reset; `.networkMocking(presets:conditionPresets:)` adds the team's own as one-tap additions |
| `.diagnosticsCapture` (Diagnostics) | `.diagnosticsCapture` | Start Capture, then the app's lines and requests, Stop and Delete; Create Report adds `console.txt` and `network.json` |
| `.bugReports` | `.bugReports` | The app's reports, annotated, one picked for Create Report (below) |
| `.pushRegistration` (Push Registration) | `.pushRegistration` | The device token with Copy Token, the APNs server, the notification settings, Refresh |
| `.scenarios`, `.authActions`, `.appStateReset`, `.environments`, `.locationSpoofing`, `.userDefaults`, `.performanceTraces`, `.appState` | the capability of the same name | As each capability's section above describes; the view hosts `.appState` as the app is reached, so every report carries it |

A plugin of your own whose model adopts
`DebugDrawerPluginModel` joins them with `DebugDrawerSidecarPlugin(id:title:icon:snapshot:command:plugin:)`,
whose closure makes the plugin's view over the transport the kit hands it. Create Report writes the
hosted plugins' report contributions, redacted by `DebugDrawer.shared.redaction`, under a summary
naming the app picked, and offers Share; with `DebugDrawer.shared.reportUploader` set, Send Report
uploads it, as in the drawer.

For a layout of your own, the pieces are public: `DebugDrawerSidecarAppList` (the apps, as they
come and go), `DebugDrawerSidecarConnection` (one app: its channel, sessions, hosted plugins and
`createReport(redaction:in:)`; host `.appState` as the app is reached, to put the app's state in
every report) and `DebugDrawerSidecarApp`. The kit builds for iOS, iPadOS and macOS,
in debug builds: like the transports it is built on, a release build gets stand-ins that list no
app, so archive a TestFlight sidecar in the Debug configuration.

**Distributing it.** The sidecar must be signed by the production app's team, as an app group
belongs to one team. TestFlight internal testers, a private Apple Business Manager app for your
organization, development or ad hoc signing, and on the Mac a notarized Developer ID app all keep
it with your team. An Apple Developer Enterprise Program account doesn't work (another Team ID, so
no shared group), and a public TestFlight link or an unlisted App Store app gives it to anyone
with the link. The receiver's "Security Model and Distribution" article
([`SecurityModel.md`](Sources/DebugDrawerReceiver/DebugDrawerReceiver.docc/SecurityModel.md))
has the details, and what to do if it leaks.

**The example pair.** `Example/Sidecar` is a sidecar built on the kit (its app file lists the
kit's plugins, and its grant server stands in for a company's), and `Example/Receiver` the
production app it drives: it links only the receiver and the capability modules, and serves every
capability the library ships, within sessions that need a grant. `just run sidecar` installs and
launches both in the iOS simulator, in `group.com.debugdrawer.example`, with the iOS example's
debug build beside them in the same group, so the sidecar lists two apps, each in its own
directory of the store; `just run sidecar macOS` launches the pair on the Mac. Pick the app in the sidecar, Open Session (the sidecar's stand-in for a
grant server signs a grant with RFC 8037's published test key, which the host trusts), and each
capability has something in the host that changes:

| Sidecar plugin | What changes in the host |
|---|---|
| Flags | Checkout (`new-checkout`) and Button Color, through the host's `DebugDrawerFeatureFlagAdapter` |
| Experiments | Checkout Flow and Onboarding's variants, through the host's `DebugDrawerExperimentAdapter`, and Analytics, which reads "Excluded from" the forced experiments until they are cleared |
| Log Levels | The Checkout and Sync subsystems' levels, through the host's `DebugDrawerLogLevelAdapter`, and Last Written, the levels Log Checkout Step wrote lines at; back to `notice` as the session ends |
| Tweaks | The greeting, a production-safe tweak; the Diagnostics tweak isn't, so the sidecar never lists it |
| Strings | The Localization Review strings, pseudo-localized or shown as keys |
| Accessibility | The window's Dynamic Type, contrast and Reduce Motion, read back beside them |
| Analytics | Record Checkout Event's event appears in the sidecar, its `email` redacted |
| MetricKit | The payloads MetricKit hands the host on a device; Crash leaves a crash diagnostic for the next launch |
| Mocking | Add on the Mock Greeting preset (the example passes it to `.networkMocking(presets:conditionPresets:)`) answers the host's Fetch Greeting, and the host shows "Network mocking active"; the Slow Greeting delay holds the answer back two seconds |
| Bug Reports | Start Capture in Diagnostics and Log Sign-In, then Report a Bug in the host (or Feedback > Report a Bug, Shift-Command-B): the report appears in the sidecar with the window's screenshot, the line and the host's state, its email redacted; type an annotation, then Create Report, and Send Report with an uploader set; the session's end deletes it in the host |
| Diagnostics | Start Capture, then Log Sign-In and Fetch Greeting: the line and the request appear in the sidecar, the email, session ID and token redacted, and the host shows "Capturing diagnostics for a sidecar"; Create Report adds them to the report, and Stop and Delete or the session's end deletes them in the host |
| Scenarios | Open Order, Show Paywall and Onboarding Step, each with its parameters: Launch brings the host forward (its `debugdrawer-receiver-example://` scheme on iOS, its bundle identifier on the Mac) and opens the scenario's screen, such as "Order #456" |
| Auth | Expire Access Token, Force Token Refresh and Log Out: the host's Sign-In reads "Signed in, access token expired", "Signed in" or "Signed out" (Sign In signs in again), and the sidecar shows each action's result, such as "Failed: Not signed in"; the host's fake token is never shown or sent |
| Environment | Switch to Staging or Canary: the host's Environment section shows its title and base URL (kept in the host; the sidecar sees only IDs and titles) and the session indicator names the backend; back to Production as the session ends |

While the session is open the host shows its own indicator (who holds the grant, until when, and
what keeps it running in the background, End Session, and Keep Running on iOS), and its Sidecar
Allowed switch is the remote kill switch: off, the session ends and its changes revert. On iOS the
host is suspended once the sidecar is in front and the keeper's background task runs out, so what
the sidecar sends waits in the store until the host returns to the foreground. On the Mac a group
named `group.` needs a provisioning profile, so `just run sidecar macOS` signs both apps with your
Apple Development identity into `<team ID>.com.debugdrawer.example`, a group macOS gives them
without asking. Signed ad hoc (no identity, or `DEBUGDRAWER_SIGN_IDENTITY=-`) the apps get no group
and share a folder in Caches instead, without a group container's protection.
Launched with `-ScriptSession <bundle ID>` (`open -g /tmp/debugdrawer-example-sidecar/DebugDrawerSidecarExample.app
--args -ScriptSession com.debugdrawer.example.receiver`), the sidecar drives a session with that app
without anyone at the screen: it opens one with a grant, overrides `new-checkout` to true, waits
for the host to report it, ends the session and waits for the flag to come back, logging each step
and the channel that carried it (`log show --predicate 'subsystem == "com.debugdrawer.example.sidecar"'`),
while the host logs its audit entries (`subsystem == "com.debugdrawer.example.receiver"`). The
receiver serves the store only, so on the Mac too the channel is the store, each command performed
as its file lands.

### The sidecar on Apple TV, Vision Pro, Apple Watch and Mac Catalyst

The transports, the receiver and `DebugDrawerAppGroupContainer` build and run on every platform
the drawer does: the store is files in the app group's container and a dispatch source on its
directory, which each platform has. Their tests run in the tvOS, visionOS and watchOS simulators
and for Mac Catalyst. The kit itself (`DebugDrawerSidecarKit`) builds for iOS, iPadOS, macOS and
watchOS, hosting on each platform the plugins that build there; on tvOS and visionOS a sidecar is
built on `DebugDrawerSidecarTransport` or `DebugDrawerAppGroupStoreTransport` directly, with views
of its own.

- **Mac Catalyst** follows iOS: a Catalyst sidecar and a Catalyst app share their group as iOS
  apps do. Catalyst apps aren't suspended, as on the Mac.
- **visionOS** follows iOS too, in its own windows: the sidecar opens beside the app, and both
  keep running while visible.
- **tvOS** has app groups, but one app runs at a time: switching to the sidecar suspends the app,
  and the background keeper's task lasts about 30 seconds (above). So on Apple TV the sidecar
  works through the store: what it leaves there is performed as the app comes back to the
  foreground, and the app's last snapshot is read meanwhile.
- **watchOS**: app groups don't span a watch and its iPhone, so **a watchOS app's sidecar is a
  watch app on the same watch**, signed by the same team and listing the same group, not the
  iPhone sidecar talking to the iPhone app and relayed over WatchConnectivity. The watch sidecar
  needs nothing the iPhone one doesn't: the same store, in the watch's own group container. A
  relay was rejected because it would put new code that carries commands into the production
  iPhone app, outside the trust boundary the app group draws; because an independent watch app
  may have no iPhone app to relay through; and because WatchConnectivity delivers a live message
  only while the other side is reachable, while its queued transfers come when the system picks.
  A backgrounded watch app is suspended (the keeper holds nothing on watchOS), so it, too, picks up
  what the sidecar left as it comes to the foreground. The socket's tests pass in the watchOS
  simulator, but the simulator runs on the Mac's kernel, so on a watch rely on the store:
  `DebugDrawerSidecarTransport` uses it whenever the socket doesn't answer.

  **A watch sidecar is built on `DebugDrawerSidecarKit`**, like the iPhone's: the same
  `DebugDrawerSidecarView` in the watch app's `WindowGroup`, laid out as the watch navigates. The
  apps are a list, each row opening the app's screen: its version and channel, its session with
  Open Session or End Session below it, a row per plugin it serves that opens the plugin, and
  Create Report. The kit hosts the capabilities' plugins there, `.featureFlagOverrides`,
  `.experimentOverrides`, `.logLevels`, `.tweaks`, `.localizationReview`,
  `.accessibilityEnvironmentOverrides`, `.analyticsEvents`, `.diagnosticsCapture`, `.bugReports`,
  `.scenarios`, `.authActions`, `.appStateReset`, `.environments`, `.userDefaults`,
  `.locationSpoofing` and `.appState`, and any `DebugDrawerSidecarPlugin` of the company's own.
  Console, Network, Performance, MetricKit, Mocking and Push Registration (`.console`, `.network`,
  `.performanceTraces`, `.metricKitPayloads`, `.networkMocking`, `.pushRegistration`) don't exist
  on watchOS, as the modules they show don't build there, so a watch sidecar names the plugins it
  shows (`plugins` defaults to none). watchOS lets one app bring another forward only through the system's own URLs, so
  `DebugDrawerSidecarApp.open(url:)` returns `false` there, and Scenarios and Reset App State say
  to open the app instead:

  ```swift
  @main
  struct CompanyWatchSidecar: App {
      var body: some Scene {
          WindowGroup {
              DebugDrawerSidecarView(
                  groupIdentifier: "group.com.example.debug",
                  plugins: [.appState, .bugReports, .environments, .userDefaults]
              )
          }
      }
  }
  ```

### What the plugins need from the app

No plugin needs an Info.plist key or an entitlement to install. Some of what they show depends on
the app's own:

| Plugin | Needs |
|---|---|
| Notifications | The `aps-environment` entitlement and a call to `registerForRemoteNotifications()` for a device token; on the Mac the entitlement needs a provisioning profile |
| Background Tasks | `BGTaskSchedulerPermittedIdentifiers`, and `UIBackgroundModes` with `fetch` for app refresh or `processing` for processing tasks |
| Permissions | The usage descriptions it lists; a request names a key the Info.plist lacks |
| Keychain, Reset App State | On the Mac, a signed `application-identifier` or `keychain-access-groups` entitlement for the data protection keychain; without one the plugin shows `errSecMissingEntitlement` |
| File Browser, UserDefaults, Databases, Reset App State | An app group in `com.apple.security.application-groups` for its container or suite; Databases and Reset App State find the app's groups on their own |
| Location | Nothing: a spoofed location is delivered whether or not the app is authorized |

The lists the plugins keep in memory have these limits:

| Plugin | Keeps | Set with |
|---|---|---|
| Console | The newest 2,000 lines | `ConsoleLogStore.shared.capacity` |
| Network | The newest 200 requests, 1 MB of each request and response body, 50 WebSocket connections of 500 frames | `NetworkStore.shared.capacity`, `installNetwork(bodyLimit:)` |
| Disk I/O | The newest 500 calls | `DiskIOStore.shared.capacity` |
| Analytics | The newest 1,000 events | `AnalyticsEvents.install(capacity:)` |
| Screen Recording | The newest 5 recordings | `ScreenRecording.install(capacity:)` |
| Crash Reports | The newest 10 reports | Fixed |
| Hangs | The newest 50 hangs | Fixed |
| MetricKit | The newest 50 payloads | Fixed |

Console and Network also keep 5 earlier launches in at most 20 MB, set at install (Console
sessions, Network sessions).

### Opening the drawer

The drawer doesn't decide how it opens. Call `DebugDrawer.shared.toggle()` from whatever trigger
makes sense for your app, or `open()` and `close()` where the trigger knows which it wants.
`isOpen` says whether the key window's drawer is open, and `$isOpen` publishes each change; open
and close the drawer with these calls rather than setting it.

```swift
// A keyboard shortcut of the app's own (Ctrl-D here)
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
| Cmd-Option-Down / Cmd-Option-Up | Scrolls to the next or previous plugin's section and moves focus to its header; with one plugin shown alone, shows the next or previous one |
| Escape | Clears the search field if it holds text, otherwise returns from a plugin shown alone to the list, otherwise closes the drawer |

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
- Menu clears the search if it holds text, otherwise returns from a plugin shown alone to the
  list, otherwise closes the drawer, while focus is in it.

tvOS has no pasteboard and no share sheet, so `DebugDrawerCopyButton` draws nothing there and a
bug report names the zip's full path in the app's container instead of offering to share it. The
HUD stays at its corner, since tvOS has no drag.

### Apple Watch

On watchOS the drawer covers the app, since a watch has no room beside it: `toggle()` opens a
full-screen list of the plugins, grouped as elsewhere (Local, Pinned, then each category, with
the pinned plugins and order the drawer saved), and a row opens that plugin's view, which the
Digital Crown scrolls. The Close button closes it, and opening a toast goes straight to its
plugin. The library binds no gesture, so the app opens the drawer from its own interface, such as
a button.

The watch list has no search, collapsing, pinning or Create a bug report; `createReport(in:)` is
still there to call. watchOS has no pasteboard, so `DebugDrawerCopyButton` draws nothing there,
and a HUD readout leaves the HUD through `toggleHUD(forPlugin:)`, since watchOS has no context
menus.

### Optional modifiers

```swift
import DebugDrawerAccessibilityPlugin
import DebugDrawerDesignOverlayPlugin
import DebugDrawerLocalizationPlugin
import DebugDrawerViewInspectorPlugin

ContentView()
    .debugLocalization()            // redraws the app's text when the Localization mode changes
    .debugAccessibilityOverrides()  // environment overrides; must be above .debugDrawer()
    .debugGrid()                    // alignment grid, controlled from the View Inspector plugin
    .debugDesignOverlay()           // the Design Overlay plugin's mockup, under the drawer
    .debugDrawer()
```

## Modules

| Module | Holds |
|---|---|
| `DebugDrawer` | The drawer: its window, the plugin protocol and registry, the views plugins are built from, and release-build stand-ins |
| `DebugDrawerReceiver` | The one product a release build may link: serves a sidecar app, over the app group's store, only the capabilities the app enables (feature flag and experiment overrides, log level elevation, diagnostics capture, bug reports the app triggers, scenarios the app registers, auth actions, environment switching among the backends the app allowlists, reading and editing the UserDefaults keys the app allowlists, or any plugin model) within sessions the sidecar opens, refusing and auditing everything else; UI-less, no interception |
| `DebugDrawerConsolePlugin` | `os_log` entries (stdout and stderr on macOS) and an app logger's lines through `ConsoleLogSink`, with metadata: level filter, text or regular-expression search, subsystem and category mutes, time range, auto-follow, copy, lines kept across launches |
| `DebugDrawerViewInspectorPlugin` | View borders by depth, alignment grid, click indicators, animation speed, render counts of the views an app tracks with `.trackRenders(_:)`, hierarchy snapshot |
| `DebugDrawerAccessibility` | The receiver capability (`.accessibilityEnvironmentOverrides()`) that lets a sidecar override Dynamic Type, Increase Contrast and Reduce Motion for its session, and the modifier the app's root view applies them with (`.accessibilityEnvironmentOverrides()`); no drawer, so a release build links it beside the receiver |
| `DebugDrawerAccessibilityPlugin` | Runtime overrides of color scheme, Dynamic Type, layout direction, locale and the system accessibility settings SwiftUI exposes, the accessibility settings each beside the system's value; re-exports `DebugDrawerAccessibility` |
| `DebugDrawerPerformancePlugin` | Live FPS, dropped frames and memory footprint with its peak, sparkline graphs, CPU per thread, and on iOS a simulated memory warning, sampled only while a drawer shows its view or HUD readout |
| `DebugDrawerEnergyPlugin` | Battery level and charging, power source, CPU load and thermal state, sampled while a drawer shows its view or between `EnergyMonitor.shared.start()` and `stop()` |
| `DebugDrawerNetwork` | `NetworkMockRule` and `NetworkConditionProfile`, real in every build, and the receiver capability (`.networkMocking(_:)`) that answers the requests a URLSession the app configured with `NetworkMockingURLProtocol` sends to the hosts it allows from a sidecar's rules, conditioned by its profiles, during a session whose grant lists it; nothing registered globally and no drawer, so a release build links it beside the receiver |
| `DebugDrawerNetworkPlugin` | URLProtocol HTTP interception: method, URL, status, timing, headers, body, cURL export, mock responses by rule, slow and failing networks per host, replay and edit-and-resend, HAR export and import, WebSocket frames, requests kept across launches, ignored hosts, GraphQL operation names; re-exports `DebugDrawerNetwork` |
| `DebugDrawerDiskIOPlugin` | FileManager, NSData and FileHandle file calls, flagging main-thread I/O and failures |
| `DebugDrawerDiskIOInterposer` | A dynamic library, linked only to opt in: dyld interposing tuples for `read`, `write`, `pread` and `pwrite`, which `unsafeInstallDiskIOWithInterposing()` turns on so Disk I/O records Swift's `Data` and `FileHandle` calls |
| `DebugDrawerAppInfo` | `AppInfoBuildMetadata`, real in every build, and the receiver capability (`.appState(_:)`) that shows a sidecar, during its session, a read-only snapshot of the app's state (`DebugDrawerAppState`): the version, build, commit, branch and CI build, and only what the app registers beside them (its flag and experiment overrides, experiment buckets, environment, a user ID hashed in the app, values of its own); UI-free, so a release build can link it |
| `DebugDrawerAppInfoPlugin` | Build (version, commit, branch, CI build), provisioning profile, entitlements, OS, memory, uptime, process, debugger, screen and reachability facts; re-exports `DebugDrawerAppInfo` |
| `DebugDrawerUserDefaultsPlugin` | Browse, search, add, edit, copy and delete UserDefaults keys of the standard defaults and app group suites, values of every property-list type edited at any depth, the list following the app's writes |
| `DebugDrawerKeychainPlugin` | Generic and internet passwords, certificates and keys, each with every attribute the keychain returns (a key's or certificate's data is never read), filtered by access group and text; generic passwords added and edited, any item deleted; on the Mac, the data protection keychain |
| `DebugDrawerScreenshotPlugin` | The app's key window captured without the drawer or the HUD: to a PNG on the Desktop or the clipboard on macOS, to the clipboard on iOS |
| `DebugDrawerFileBrowserPlugin` | The app's Documents, Library, tmp, bundle and app group containers, with folder totals and dates, previews of text, JSON, property lists and images, and files imported, renamed, deleted and shared, the bundle read-only |
| `DebugDrawerLocation` | `LocationCoordinate`, real in every build, and the high-risk receiver capability (`.locationSpoofing(_:)`) that lets a sidecar, within its session, replace the locations the app reads through `LocationSpoofing` with a coordinate of its own, telling the app as spoofing starts and ends so its own fraud checks can react; no interception and no drawer, so a release build links it beside the receiver |
| `DebugDrawerLocationPlugin` | Spoofed CLLocationManager locations: presets, a custom latitude and longitude, and GPX routes played at a chosen speed |; re-exports `DebugDrawerLocation`
| `DebugDrawerLoadedLibrariesPlugin` | Every loaded image, grouped as app, third-party and system, with UUIDs and load addresses |
| `DebugDrawerDeepLinkPlugin` | Opens URLs in the app's own handler or through the system, continues universal links and activities of the app's own type with their userInfo in the app, and keeps a history of each |
| `DebugDrawerCookiesPlugin` | Browse, search, copy and delete `HTTPCookieStorage.shared`'s cookies, and `WKWebsiteDataStore.default()`'s where WebKit exists |
| `DebugDrawerLaunchTimePlugin` | Launch time: process start to `installLaunchTime()` (pre-main), from there to the first frame, and the total |
| `DebugDrawerTweaks` | Tweak declarations, their storage and typed accessors, real in every build, and the receiver capability (`.tweaks(...)`) that lets a sidecar change the tweaks marked production-safe; UI-free, so a release build links it beside the receiver |
| `DebugDrawerTweaksPlugin` | The app's own debug settings: toggles, pickers, text fields, steppers and actions, in sections, read through typed accessors; re-exports `DebugDrawerTweaks` |
| `DebugDrawerFeatureFlagsPlugin` | The app's feature flags through an adapter to its flag service: live values, local overrides that persist, search, an overridden-only filter and Reset All |
| `DebugDrawerCrashReportsPlugin` | Uncaught exceptions and fatal signals, handed on to the app's other crash handlers, shown on the next launch with a badge and stack trace; MetricKit crash diagnostics too |
| `DebugDrawerHangDetector` | The main-thread stall monitor, real in every build, and the receiver capability (`.performanceTraces(_:)`) that records the hitches, the hangs with their main-thread stacks (addresses, image UUIDs and offsets, for a dSYM) and the signpost intervals the app marks on `PerformanceTraces`, while a sidecar records in its session; UI-free, so a release build links it beside the receiver |
| `DebugDrawerHangDetectorPlugin` | Main-thread hangs over a threshold the drawer can change, each with its duration and the stack it was stuck on, a toast and a badge; MetricKit hang diagnostics too; re-exports `DebugDrawerHangDetector` |
| `DebugDrawerLeakDetectorPlugin` | View controllers still alive a run-loop turn after their screen was dismissed, and opted-in classes with more live instances than allowed, by class with a count, a toast and a badge |
| `DebugDrawerMetricKit` | MetricKit's payload kinds and subscriber, real in every build, and the receiver capability (`.metricKitPayloads(sessions:directory:redaction:capacity:)`) that keeps the payloads the app receives, crash diagnostics among them, redacted by `MetricKitRedaction` and across launches, and serves them while a sidecar's session is open; UI-free, so a release build links it beside the receiver |
| `DebugDrawerMetricKitPlugin` | MetricKit's metric and diagnostic payloads, kept across launches and listed by date with a summary, each open as formatted JSON to copy or export; a toast and a badge for new ones; re-exports `DebugDrawerMetricKit` |
| `DebugDrawerPermissionsPlugin` | Every privacy permission the app declares in its Info.plist, with its live status, a button that asks when it is undecided and one that opens Settings |
| `DebugDrawerNotifications` | The app's notification settings, real in every build, and the receiver capability (`.pushRegistration(_:)`) that shows a sidecar the APNs device token the app hands `PushRegistrationMirror`, the push environment (`PushEnvironment`) and the notification authorization and settings, only while a session is open; read-only and UI-free, so a release build links it beside the receiver |
| `DebugDrawerNotificationsPlugin` | The APNs device token to copy, notification authorization and settings, pending and delivered notifications to inspect and remove, and a pasted APNs payload sent as a local notification; re-exports `DebugDrawerNotifications` |
| `DebugDrawerBackgroundTasksPlugin` | The BGTaskScheduler identifiers the Info.plist permits and the pending task requests, with their kind and earliest begin date, each cancellable; a request scheduled on demand, and the LLDB commands that simulate a launch or an expiration |
| `DebugDrawerAnalytics` | The analytics sink (`AnalyticsEvents.record`) and `AnalyticsValue`, real in every build, and the receiver capability (`.analyticsEvents(sessions:redaction:capacity:)`) that mirrors the events recorded during a sidecar's session, redacted by `AnalyticsRedaction` in the app; UI-free, so a release build links it beside the receiver |
| `DebugDrawerAnalyticsPlugin` | The analytics events the app records, live, newest first, with their time and properties: search by name, key or value, each open as inspector rows and JSON to copy, all exported as a JSON file; re-exports `DebugDrawerAnalytics` |
| `DebugDrawerDatabaseBrowserPlugin` | The app's SQLite, Core Data and SwiftData stores, opened read-only: tables or entities with row counts, rows paged and searched in a grid, and read-only SELECT queries, copied as CSV |
| `DebugDrawerLocalization` | `Localization`'s modes and pseudo-localization, real in every build, and the receiver capability (`.localizationReview()`) that lets a sidecar show the keys or pseudo-localized text of the strings the app reads through `LocalizationReview`, for its session; no interception and no drawer, so a release build links it beside the receiver |
| `DebugDrawerLocalizationPlugin` | Pseudo-localization and show-keys modes over the strings the app looks up through Bundle, live, Apple's localization launch arguments to copy, and the translations missing for a language, grouped by table, searched and copied as text or CSV; re-exports `DebugDrawerLocalization` |
| `DebugDrawerScreenRecordingPlugin` | The app's windows recorded as a QuickTime movie without the drawer, its HUD or its toasts, started and stopped from the drawer or the HUD, with touch indicators on iOS: the saved recordings to share or delete, and the newest in the bug report |
| `DebugDrawerDesignOverlayPlugin` | A design mockup over the app's content, picked from Photos or Files on iOS or a file or the pasteboard on macOS: opacity, an offset set by steppers or by dragging in Move mode, the scale, and a difference blend that shows pixel drift; touches pass through to the app |
| `DebugDrawerColorVisionPlugin` | Protanopia, deuteranopia, tritanopia and grayscale simulated live over the views marked `.debugColorVision()`, in linear RGB with Machado et al.'s matrices, picked in the drawer or cycled from the HUD, while the drawer keeps its colors |
| `DebugDrawerAppStateReset` | The receiver capability (`.appStateReset(_:)`) that lets a sidecar reset the categories a production app allows (never the keychain unless it opts in), listed and confirmed by revision, applied on the next foreground; no drawer, so a release build links it beside the receiver |
| `DebugDrawerAppStateResetPlugin` | The app's state cleared as a fresh install leaves it, by category: UserDefaults, keychain items, the container's files, caches, cookies, the URL cache and the app's own cleanup, each listed before a confirmation, then relaunched on macOS or quit elsewhere; re-exports `DebugDrawerAppStateReset` |
| `DebugDrawerRemote` | Plugin models served to a viewer on another device over the local network: an opt-in Network.framework server advertised over Bonjour, each viewer paired with a six-digit code the device shows (and its Remote Viewing plugin, which shows the codes), and the viewer's transport and browser |
| `DebugDrawerSidecarKit` | A sidecar app, as a library: `DebugDrawerSidecarView` lists the apps in the group that serve a sidecar, opens their sessions (with a grant the company's server gives, when they require one), shows their Console and Network, a plugin for every capability the receiver ships (Flags, Experiments, Log Levels, Tweaks, Strings, Accessibility, Analytics, MetricKit, Mocking, Diagnostics, Bug Reports, Push Registration, Scenarios, Auth, Reset App State, Environment, Location, UserDefaults, Performance, App State) and other model-backed plugins over the socket or the store, and makes and uploads a report of them, the app state attached to each; iOS, iPadOS and macOS, and watchOS without Console, Network, Performance, MetricKit, Mocking and Push Registration; debug builds |

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
| `just generate` | An Xcode project from the Bazel graph, `xcode/DebugDrawer.xcodeproj`, opened in Xcode (`--no-open` only writes it) |
| `just run [macOS\|iOS\|appkit\|uikit\|sidecar\|catalyst\|visionOS\|tvOS\|watchOS]` | Build and launch an example app (`just run sidecar [iOS\|macOS]`: the example sidecar beside the production host it drives, "The example pair" above); each has a Test Bench of actions that give every plugin something to show (`-RunTestBench all` runs them at launch). The Mac example is signed with your Apple Development certificate when the Keychain has one, so macOS keeps its Location and other privacy grants across rebuilds; set `DEBUGDRAWER_SIGN_IDENTITY` to choose another identity, or `-` to sign ad hoc |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

MIT. See `LICENSE`.
