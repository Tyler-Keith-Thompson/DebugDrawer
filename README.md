# DebugDrawer

A plugin-based debug drawer for macOS and iOS apps: a slide-in panel of debugging tools, each its
own library, so an app links only the tools it wants. Built for SwiftUI. Every entry point compiles
to a no-op outside `DEBUG`, so builds that ship to end users carry none of it.

## Installation

DebugDrawer requires Swift 6.3 and supports macOS 15 and iOS 17 or later. The core module,
`DebugDrawer` (the drawer, the plugin protocol and the shared views), also builds for visionOS 1
or later, where the drawer opens in an ornament beside the window rather than over it, and for
tvOS 17 or later, where the remote's focus moves through it (Apple TV, below), and for watchOS 10
or later, where it is a list of the plugins (Apple Watch, below). The shipped plugins build for
macOS and iOS only so far, so a visionOS, tvOS or watchOS app registers plugins of its own.
iOS includes Mac Catalyst: an iOS app built for the Mac shows the iOS drawer in its window.

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

#if DEBUG
DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)
#endif
```

`DebugDrawerReportUploader` exists in every configuration too, so the uploader compiles in
release, where nothing calls it.

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
Tweaks takes the settings it shows and Feature Flags the adapter it reads, and Crash Reports,
Hangs, Leaks, MetricKit, Permissions, Notifications, Background Tasks, Analytics and Databases install outside `#if DEBUG`, so each has a
section of its own, next.

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

#if DEBUG
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
#endif

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

#if DEBUG
DebugDrawer.shared.installFeatureFlags(provider: appFlags)
#endif

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
when, the app's version, the crashed thread's frames, named by `backtrace_symbols_fd`) and then
calls the handler that was installed before it, so a crash SDK the app also uses still records
the crash; install after the SDK for that. The signal handler runs on an alternate stack, so a
stack overflow on the thread that installed is recorded too. Where MetricKit exists (iOS, macOS,
visionOS), the `MXCrashDiagnostic`s the system delivers, often a day later, are kept as reports
as well.

On the next launch the plugin keeps the report with the others (the newest ten, in the app's
Application Support directory; `install(directory:)` takes another), puts a badge on its header
for each report not yet opened and posts a toast. The drawer lists them newest first; opening one
shows its stack trace, selectable, with a button that copies the whole report, and marks it seen.
Mark All Seen clears the badge, and each report can be deleted, or all of them. A bug report
carries every report as a text file.

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
Where MetricKit exists (iOS, macOS, visionOS), the `MXHangDiagnostic`s the system delivers are
listed as well.

With no hang, the cost is a clock read and an uncontended lock on each turn of the main run loop,
and a watcher wake four times per threshold that does the same; `HangDetectorOverheadTests`
measures both. The drawer lists the hangs of this run newest first (the newest fifty); opening one
shows its stack, selectable, with a button that copies it, and marks it seen. Its Threshold picker
changes the threshold while the app runs. Mark All Seen clears the badge, Clear All forgets them,
and a bug report carries them all in `hangs.txt`.

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
they do nothing. In debug builds `install()` subscribes to `MXMetricManager` where MetricKit
exists (iOS, macOS, visionOS; macOS reports a subset of the metrics), and first keeps the payloads
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

`PrivacyPermissions` exists in every configuration, so the call needs no `#if DEBUG`: in release
it does nothing, and the plugin references none of the frameworks that report a status. In debug
builds each permission shows its name, its status (Allowed, While Using, Limited, Denied,
Restricted, Not Asked and so on, each with its own symbol and color), and the usage descriptions
that declare it with their keys:

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

- **APNs Device Token**: the token as hexadecimal with Copy Token, or why registering failed. It
  is a device identifier, so it is masked under the drawer's redaction rules (the standard rules
  mask any key containing `token`) until the eye button reveals it, and in bug reports; Copy Token
  copies the token itself, for pasting into a push tool. The simulator gives a token to an app
  whose entitlements declare `aps-environment`; on the Mac that entitlement needs a provisioning
  profile.
- **Authorization**: the status (Allowed, Denied, Provisional, Not Asked and so on), each
  presentation setting (alerts, sounds, badges, lock screen, Notification Center, critical, time
  sensitive, alert style, previews), Request while the user hasn't decided, and Refresh.
- **Send a Payload**: an editor for an APNs payload, checked as it is typed, and a delay (now, 5 or
  30 seconds, long enough to put the app in the background). `aps` gives the alert (a string, or a
  dictionary with `title`, `subtitle` and `body`), `badge`, `sound` (`default`, a file name, or a
  critical sound dictionary), `category`, `thread-id`, `target-content-id`, `interruption-level`
  and `relevance-score`; the whole payload, `aps` and every key beside it, becomes the
  notification's `userInfo`, as the app's handlers would get it from APNs. Notes say what a local
  notification does differently: localization keys show as the keys themselves,
  `content-available` doesn't wake the app in the background, `mutable-content` doesn't run a
  notification service extension, and a payload over 4 KB would be refused by APNs. Sending asks
  for authorization first if the user hasn't decided.
- **Pending** and **Delivered**: each request and notification with its title, subtitle, body,
  identifier, trigger (after an interval, on a date, at a location) or delivery time, category,
  thread, badge and `userInfo`, each removable, and Remove All.

While the app is in front, the system shows a notification only if the app's
`UNUserNotificationCenterDelegate` asks for a banner in `userNotificationCenter(_:willPresent:)`;
the plugin never takes the delegate, which stays the app's. It reads the center when installed,
each time the app becomes active, after each of its own actions and on Refresh; nothing polls. To
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

- **Permitted Identifiers**: each identifier, whether a request for it is pending, a Schedule
  button for each kind the `UIBackgroundModes` allow (App Refresh for `fetch`, Processing for
  `processing`), which submits a request that may begin now, and a copy button for its LLDB
  commands. A refused request shows why on its row: unavailable (the simulator, or Background App
  Refresh turned off), not permitted, or too many pending. A wildcard identifier (`….*`, for
  continued processing tasks) is listed with what it is for. Without the modes the section warns
  that the system runs no request.
- **Pending Requests**: each request with its identifier, kind (app refresh or processing, with
  whether it needs network or external power) and earliest begin date, each cancellable, with
  Cancel All and Refresh.

The plugin registers no launch handlers: `BGTaskScheduler` requires the app's own, registered for
every permitted identifier before it finishes launching
(`BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` in
`application(_:didFinishLaunchingWithOptions:)`).

To run a task's launch handler now, on a device (the simulator runs no background tasks):

1. Schedule a request for the identifier, from the drawer or from the app's own code.
2. Copy its launch command with the copy button beside the identifier:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.refresh"]`
3. Pause the app in Xcode (Debug ▸ Pause, or the pause button in the debug bar), paste the command
   at the `(lldb)` prompt, press Return, and continue the app. The system launches the task as it
   would in the background.
4. To test the expiration handler, pause again while the task runs and paste its expiration
   command, `_simulateExpirationForTaskWithIdentifier:` with the same identifier.

The drawer only copies these commands: the selectors are private API, which the app itself never
calls. It reads the pending requests when installed, each time the app becomes active, after each
of its own actions and on Refresh; nothing polls. A bug report carries `background-tasks.txt`: the
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
`#if DEBUG`. The plugin looks in Application Support, Documents and the containers of the app
groups the app's entitlements name (and in `additionalDirectories`), for `.sqlite`, `.sqlite3`,
`.db` and `.store` files that begin with SQLite's header; `-wal`, `-shm` and `-journal` files belong
to their store and aren't listed apart. A Mac app outside the sandbox has only its own folder of
Application Support searched, and no Documents. Each store shows its path, size, journal mode and
kind; a Core Data or SwiftData store (one with `Z_METADATA` and `Z_PRIMARYKEY`) lists its tables
by entity name, with the `Z` table beneath, and its model's version hash. Opening a table pages its
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
| `just run [macOS\|iOS\|catalyst\|visionOS\|tvOS\|watchOS]` | Build and launch the example app |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

MIT. See `LICENSE`.
