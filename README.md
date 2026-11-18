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
    .package(url: "https://github.com/Tyler-Keith-Thompson/DebugDrawer", from: "0.1.2"),
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
window's drawer opens and closes on its own; `toggle()` and `isOpen` act on the key window's
(on iPadOS, the scene with the key window, or else the foreground-active one), and `toggle(in:)`
on the `NSWindow` or `UIWindowScene` it is given, attaching it first if it isn't yet. The plugin
registry is shared, but each window's drawer lists only the local plugins of its own views. A
UIKit or AppKit app without `debugDrawer()` attaches it with `DebugDrawer.shared.attach(to:)`,
passing each `UIWindowScene` or `NSWindow`, and gets the same drawer with every global plugin (the
HUD and the toasts are drawn by `debugDrawer()`, so such a window shows neither). A section header's chevron, or the jump bar's menu, shows
one plugin alone at the panel's full height, and the back button returns to the list.

A local plugin is registered when its view appears and removed when it disappears, unless a newer
view has registered a plugin with the same `id` since. A plugin that shows data of its own (an
order's ID, a folder's path) declares a `contentIdentifier` that changes with it, and
`.debugLocalPlugin()` registers the plugin again each time it changes; it defaults to `id`. A plugin
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

Network's Copy cURL, Keychain's and UserDefaults' Copy Value and Cookies' Copy mask what the
drawer's redaction rules call sensitive, and the same values are masked on screen until the eye
button beside them reveals them. Revealing never changes a copy. The rules start as
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
let zip = try DebugDrawer.shared.createReport() // the same zip the button makes
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
  its view or its HUD readout is on screen.
- **Energy** shows the battery's level, whether it is charging, the power source, the thermal
  state and this process's CPU load (not Xcode's Energy Impact, which also weighs the GPU, network,
  location and wakeups), with two minutes of history. It samples once a second while its view is on
  screen, or between the app's own `EnergyMonitor.shared.start()` and `stop()`. A Mac without a
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
  those beside the system's value. Reset All clears them; they last until the app quits.
- **View Inspector** draws a border around every AppKit or UIKit view in the key window, colored
  by its depth, the alignment grid where `.debugGrid()` is applied, a ripple where each click or
  touch lands, slows animations up to ten times, and lists the key window's view hierarchy with
  each view's class and accessibility label. Its render counts follow below (View Inspector).

### Deep links: universal links and user activities

Opening an https URL goes to the browser, so a universal link, a Handoff or a Spotlight result
can't be tested by opening a URL. The Deep Link Tester continues one in the app instead, as the
system does: an https URL in the field is sent as an `NSUserActivity` of type
`NSUserActivityTypeBrowsingWeb` with that `webpageURL`, and Activity mode sends an activity of the
app's own type with a userInfo of strings, numbers and Booleans. Sent activities are listed apart
from the URLs opened, and a tap puts one back in the form.

A SwiftUI app's `onContinueUserActivity` has no public entry point, so a SwiftUI app passes the
plugin the code that handles an activity:

```swift
import DebugDrawerDeepLinkPlugin
import Foundation

/// The app's router: `onContinueUserActivity` hands it the activities the system continues.
@MainActor
final class Router {
    private(set) var path: [String] = []

    func handle(_ activity: NSUserActivity) {
        if let url = activity.webpageURL {
            path.append(url.path)
        }
    }
}

let router = Router()

DebugDrawer.shared.installDeepLink(continueUserActivity: router.handle)
```

Without a handler, an activity goes where the system sends it in a UIKit or AppKit app: on iOS,
the first window scene delegate with `scene(_:continue:)`, else the app delegate's
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
network path (Wi-Fi, cellular, Ethernet or offline) and when the process started.
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
with the start and the app's version, then one line per log line, with its time, level, source,
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
`URLSessionConfiguration` made from then on, so the log shows the http and https requests of the
shared session and of every session made after the call, those of networking libraries built on
`URLSession` included. A session made before the call keeps the configuration it had, so install at
startup. What doesn't go through a URL protocol isn't seen: background sessions, web views,
AVFoundation's streaming, Network.framework's connections and stream tasks. WebSocket tasks are
recorded on the tasks themselves (Network WebSockets, below).

The plugin sends each request it captures on a session of its own, with the default
configuration, and hands the response to the app's task. The request goes out as the app made it,
with no header added, but the app's own session's delegate, cache, cookie storage and timeouts
don't apply to it, and redirects are followed for it. A body the app streams is sent with its
length (`Content-Length`) rather than in chunks. The log keeps the newest 200 requests (set
`NetworkStore.shared.capacity` for another number) and the first megabyte of each request and
response body, marked truncated with its full size beyond that; `installNetwork(bodyLimit:)` takes
another limit. The server and the app always get the whole body.

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
has run.

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
drawer and nothing is stored: `value` is always the declared default and `publisher` sends only
that. Mark a tweak `.productionSafe()` to say it may be offered outside debug builds; the drawer
shows it the same either way.

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
The `MXHangDiagnostic`s MetricKit delivers, which describe earlier runs, are listed as well,
with a badge but no toast.

With no hang, the cost is a clock read and an uncontended lock on each turn of the main run loop,
and a watcher wake four times per threshold that does the same; `HangDetectorOverheadTests` measures
both. The drawer lists the hangs newest first (the newest fifty); opening one shows its stack,
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
need no `#if DEBUG`: in release they do nothing, and the plugin references nothing of User
Notifications. In debug builds the plugin shows:

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
- **Pending** and **Delivered**, each with its count: each request and notification with its title,
  subtitle, body, identifier, trigger (after an interval, on a date, at a location) or delivery
  time, category, thread, badge and `userInfo`, each removable, and Remove All.

While the app is in front, the system shows a notification only if the app's
`UNUserNotificationCenterDelegate` asks for a banner in `userNotificationCenter(_:willPresent:)`;
the plugin never takes the delegate, which stays the app's. It reads the center when installed,
each time the app becomes active, after a request or a send and on Refresh; nothing polls. To
send a real remote notification to the simulator from the Mac instead, `xcrun simctl push
<device> <bundle id> payload.json` takes the same JSON. A bug report carries `notifications.txt`:
the token (masked), the settings, and every pending and delivered notification.

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
`#if DEBUG`: in release they do nothing, and `record` doesn't even evaluate its arguments. In
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
batches, one per turn of the main queue, however many the app makes. The Disk section shows how
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
window is left out, and the HUD and toasts `.debugDrawer()` draws above the app are hidden for the
moment a frame is drawn and shown again before the screen updates. Pin it to the HUD (Show in HUD)
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
on: the UserDefaults keys starting `com.debugdrawer.` (the drawer's layout, HUD pins and plugin
settings) and the files named `DebugDrawer…` in each directory and in its folder named after the
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
Caches' one. The plugin builds for macOS, iOS, Mac Catalyst, visionOS and tvOS.

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
makes sense for your app:

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
| `DebugDrawerConsolePlugin` | `os_log` entries (stdout and stderr on macOS) and an app logger's lines through `ConsoleLogSink`, with metadata: level filter, text or regular-expression search, subsystem and category mutes, time range, auto-follow, copy, lines kept across launches |
| `DebugDrawerViewInspectorPlugin` | View borders by depth, alignment grid, click indicators, animation speed, render counts of the views an app tracks with `.trackRenders(_:)`, hierarchy snapshot |
| `DebugDrawerAccessibilityPlugin` | Runtime overrides of color scheme, Dynamic Type, layout direction, locale and the system accessibility settings SwiftUI exposes, the accessibility settings each beside the system's value |
| `DebugDrawerPerformancePlugin` | Live FPS, dropped frames and memory footprint with its peak, sparkline graphs, CPU per thread, and on iOS a simulated memory warning, sampled only while its view or HUD readout shows |
| `DebugDrawerEnergyPlugin` | Battery level and charging, power source, CPU load and thermal state, sampled while its view shows or between `EnergyMonitor.shared.start()` and `stop()` |
| `DebugDrawerNetworkPlugin` | URLProtocol HTTP interception: method, URL, status, timing, headers, body, cURL export, mock responses by rule, slow and failing networks per host, replay and edit-and-resend, HAR export and import, WebSocket frames, requests kept across launches, ignored hosts, GraphQL operation names |
| `DebugDrawerDiskIOPlugin` | FileManager, NSData and FileHandle file calls, flagging main-thread I/O and failures |
| `DebugDrawerDiskIOInterposer` | A dynamic library, linked only to opt in: dyld interposing tuples for `read`, `write`, `pread` and `pwrite`, which `unsafeInstallDiskIOWithInterposing()` turns on so Disk I/O records Swift's `Data` and `FileHandle` calls |
| `DebugDrawerAppInfoPlugin` | Build (version, commit, branch, CI build), provisioning profile, entitlements, OS, memory, uptime, process, debugger, screen and reachability facts |
| `DebugDrawerUserDefaultsPlugin` | Browse, search, add, edit, copy and delete UserDefaults keys of the standard defaults and app group suites, values of every property-list type edited at any depth, the list following the app's writes |
| `DebugDrawerKeychainPlugin` | Generic and internet passwords, certificates and keys, each with every attribute the keychain returns (a key's or certificate's data is never read), filtered by access group and text; generic passwords added and edited, any item deleted; on the Mac, the data protection keychain |
| `DebugDrawerScreenshotPlugin` | The app's key window captured without the drawer or the HUD: to a PNG on the Desktop or the clipboard on macOS, to the clipboard on iOS |
| `DebugDrawerFileBrowserPlugin` | The app's Documents, Library, tmp, bundle and app group containers, with folder totals and dates, previews of text, JSON, property lists and images, and files imported, renamed, deleted and shared, the bundle read-only |
| `DebugDrawerLocationPlugin` | Spoofed CLLocationManager locations: presets, a custom latitude and longitude, and GPX routes played at a chosen speed |
| `DebugDrawerLoadedLibrariesPlugin` | Every loaded image, grouped as app, third-party and system, with UUIDs and load addresses |
| `DebugDrawerDeepLinkPlugin` | Opens URLs, continues universal links and activities of the app's own type with their userInfo in the app, and keeps a history of each |
| `DebugDrawerCookiesPlugin` | Browse, search, copy and delete `HTTPCookieStorage.shared`'s cookies, and `WKWebsiteDataStore.default()`'s where WebKit exists |
| `DebugDrawerLaunchTimePlugin` | Launch time: process start to `installLaunchTime()` (pre-main), from there to the first frame, and the total |
| `DebugDrawerTweaksPlugin` | The app's own debug settings: toggles, pickers, text fields, steppers and actions, in sections, read through typed accessors |
| `DebugDrawerFeatureFlagsPlugin` | The app's feature flags through an adapter to its flag service: live values, local overrides that persist, search, an overridden-only filter and Reset All |
| `DebugDrawerCrashReportsPlugin` | Uncaught exceptions and fatal signals, handed on to the app's other crash handlers, shown on the next launch with a badge and stack trace; MetricKit crash diagnostics too |
| `DebugDrawerHangDetectorPlugin` | Main-thread hangs over a threshold the drawer can change, each with its duration and the stack it was stuck on, a toast and a badge; MetricKit hang diagnostics too |
| `DebugDrawerLeakDetectorPlugin` | View controllers still alive a run-loop turn after their screen was dismissed, and opted-in classes with more live instances than allowed, by class with a count, a toast and a badge |
| `DebugDrawerMetricKitPlugin` | MetricKit's metric and diagnostic payloads, kept across launches and listed by date with a summary, each open as formatted JSON to copy or export; a toast and a badge for new ones |
| `DebugDrawerPermissionsPlugin` | Every privacy permission the app declares in its Info.plist, with its live status, a button that asks when it is undecided and one that opens Settings |
| `DebugDrawerNotificationsPlugin` | The APNs device token to copy, notification authorization and settings, pending and delivered notifications to inspect and remove, and a pasted APNs payload sent as a local notification |
| `DebugDrawerBackgroundTasksPlugin` | The BGTaskScheduler identifiers the Info.plist permits and the pending task requests, with their kind and earliest begin date, each cancellable; a request scheduled on demand, and the LLDB commands that simulate a launch or an expiration |
| `DebugDrawerAnalyticsPlugin` | The analytics events the app records, live, newest first, with their time and properties: search by name, key or value, each open as inspector rows and JSON to copy, all exported as a JSON file |
| `DebugDrawerDatabaseBrowserPlugin` | The app's SQLite, Core Data and SwiftData stores, opened read-only: tables or entities with row counts, rows paged and searched in a grid, and read-only SELECT queries, copied as CSV |
| `DebugDrawerLocalizationPlugin` | Pseudo-localization and show-keys modes over the strings the app looks up through Bundle, live, Apple's localization launch arguments to copy, and the translations missing for a language, grouped by table, searched and copied as text or CSV |
| `DebugDrawerScreenRecordingPlugin` | The app's windows recorded as a QuickTime movie without the drawer, its HUD or its toasts, started and stopped from the drawer or the HUD, with touch indicators on iOS: the saved recordings to share or delete, and the newest in the bug report |
| `DebugDrawerDesignOverlayPlugin` | A design mockup over the app's content, picked from Photos or Files on iOS or a file or the pasteboard on macOS: opacity, an offset set by steppers or by dragging in Move mode, the scale, and a difference blend that shows pixel drift; touches pass through to the app |
| `DebugDrawerColorVisionPlugin` | Protanopia, deuteranopia, tritanopia and grayscale simulated live over the views marked `.debugColorVision()`, in linear RGB with Machado et al.'s matrices, picked in the drawer or cycled from the HUD, while the drawer keeps its colors |
| `DebugDrawerAppStateResetPlugin` | The app's state cleared as a fresh install leaves it, by category: UserDefaults, keychain items, the container's files, caches, cookies, the URL cache and the app's own cleanup, each listed before a confirmation, then relaunched on macOS or quit elsewhere |

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
| `just run [macOS\|iOS\|appkit\|uikit\|catalyst\|visionOS\|tvOS\|watchOS]` | Build and launch an example app; each has a Test Bench of actions that give every plugin something to show (`-RunTestBench all` runs them at launch) |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

MIT. See `LICENSE`.
