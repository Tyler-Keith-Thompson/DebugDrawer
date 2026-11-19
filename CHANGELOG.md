# Changelog

Notable changes in each release, newest first, in the style of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Work lands under Unreleased; before
`just deploy`, rename that heading to the new version and date (`## [0.1.2] - 2026-11-17`), start a
new empty Unreleased above it, and commit. Deploy refuses to tag a version with no entry here, and
the entry becomes the GitHub release's notes.

## [Unreleased]

### Added

- DD-153: `DebugDrawer.setNoticesMuted(_:forPlugin:)` and `isNoticesMuted(forPlugin:)` silence a plugin's badges and toasts, keyed by its ID and saved in `UserDefaults` across launches. Silencing removes the badge and toast it shows and drops what it posts until it is allowed again. Each section header's context menu offers Silence Notices and Allow Notices, and a silenced header shows a crossed-out bell.
- DD-90: `CaptureBuffer`, a bounded capture buffer in the plugin contract: the newest elements within a count and a byte total, appended from any thread, each with a stable ID, a generation that grows with every change, counts of what it evicted, and `Codable` snapshots for export. Console, Network and Disk I/O keep their captures in it, with new `byteCapacity` properties on `ConsoleLogStore` (4 MiB), `NetworkStore` (32 MiB of bodies) and `DiskIOStore` (1 MiB of paths).
- DD-85: `installDeepLink(presets:continueUserActivity:openURL:)` and `DeepLinkPreset`: an app passes the Deep Link Tester its own presets and an `openURL` handler, which receives each URL the plugin opens in place of the system and returns whether it handled it. Presets default to `DeepLinkPreset.bundleURLSchemes`, one per scheme the app's Info.plist declares, with an empty state saying how to add some when there are none. `installDeepLink(continueUserActivity:)` remains, deprecated, and forwards to it.
- DD-199: `NetworkEntry.requestBodySize`, `isRequestBodyTruncated` and `requestSizeLabel`: Network keeps each request body to `installNetwork(bodyLimit:)`, as it does each response body, marked truncated with its full size.
- DD-5: `DebugDrawer.toggle(in:)` opens or closes the drawer in the `NSWindow` (macOS) or `UIWindowScene` (iOS) it is given, attaching it first if it isn't yet, whichever window is key; the macOS example opens a second window (Debug > New Window, or `-NewWindow` at launch).
- DD-84: HTTP Cookies lists the cookies web views keep in `WKWebsiteDataStore.default()` beside `HTTPCookieStorage.shared`'s, where WebKit exists, each row marked URLSession or WKWebView, and deletes each from its own store.
- DD-72: `DebugDrawer.unsafeInstallDiskIOWithInterposing()` and `DiskIOStore.unsafeInstallWithInterposing()`, with a new dynamic library product, `DebugDrawerDiskIOInterposer`: in an app that links it, Disk I/O also records Swift's `Data.write(to:)`, `Data(contentsOf:)` and `FileHandle.write(contentsOf:)` (each `read`, `write`, `pread` and `pwrite` on a regular file no swizzled method records), with their bytes and thread. It relies on dyld interposing, undocumented behaviour a new OS can change, so it is opt-in and debug-only; the README says how to link it and what it risks. `installDiskIO()` is unchanged.

### Changed

- DD-85: each example app declares a URL scheme of its own (`debugdrawer-example`, `-ios`, `-uikit`, `-appkit`), which the Deep Link Tester lists as its preset, and routes the URLs the tester opens through `openURL`, showing the last one in its window.
- DD-4: the UIKit example (`Example/iOSUIKit`) has no SwiftUI root and installs every global plugin, and the macOS example opens an AppKit-only window (Debug > Show AppKit Window, or `-AppKitWindow` at launch), each attaching the drawer with `DebugDrawer.shared.attach(to:)`; the docs say a window with no SwiftUI view under `debugDrawer()` shows the drawer without the HUD and toasts.
- DD-60: every example app has a Test Bench, actions grouped by plugin that give each one data (requests that succeed, fail with 404 and never resolve, a WebSocket, a line at every log level, main-thread file I/O, defaults, keychain and cookie writes, a leak, a hang and a crash), run at launch with `-RunTestBench <ids>|all`; an AppKit-only Mac example joins the UIKit one (`just run appkit`, `just run uikit`).

### Fixed

- DD-229: `just spm-test`, `just test-spm` and `just spm-test-mac` run with no arguments no longer hand `swift test` an empty argument ("Unexpected argument ''"), which also stopped `just deploy` at its verify step.
- DD-174: Crash Reports and Hang Detector show each Swift frame's symbol demangled, as Xcode does (`static ExampleApp_iOS.ExampleCrash.crash() -> Swift.Never` rather than its mangled `$s…` name), with the Swift runtime's own demangler; Copy Report still copies the stack as it was recorded.
- DD-225: File Browser's actions fit on one line at the drawer's 316 pt width, light and dark and at every Dynamic Type size: a folder shows Refresh and a file Share…, beside an icon-only More menu holding Import…, Copy Path, Copy Text, Reveal in Finder, Rename… and Delete (destructive, still confirmed in place under the row).
- DD-196: Disk I/O costs a recorded file call about as much as it did before DD-72 when the app's main thread is idle, where each call is delivered on its own: `DiskIOStore.events` changes in place rather than as a whole new list each delivery, the wake-up is a plain block on the main queue, and `attributesOfItem(atPath:)` reads the size without bridging the attributes. `DiskIOStore.events` is now backed by `NewestFirst`, a new property wrapper; reading it and `$events` work as before.
- DD-74: a plugin's default `id` is its type's fully qualified name (`MyApp.CachePlugin`), so two modules' plugins of one name both appear, and state saved under the old unqualified name moves to the new id when the plugin registers; a global plugin of another type registered under an `id` already taken is still left out, now with an error logged naming both types; `.debugLocalPlugin()` shows the plugin's latest value as its view updates, so `contentIdentifier` is deprecated and unused; the drawer's own state (collapsed sections, layout, HUD, silenced notices, Deep Link's history, Location's simulated location, Screen Recording's Show Touches) lives in a defaults suite of its own, `<bundle identifier>.debugdrawer`, moved there once from the app's standard defaults; the shipped plugins keep their ids.
- DD-63: installing Network no longer changes how the app's sessions behave. Each captured request is sent with a copy of its own session's configuration, so an ephemeral session's cookies and cached responses stay out of the shared storage and cache, and the session's extra headers, timeouts, proxy and TLS settings apply. Redirects and authentication challenges go to the app's session delegate: a redirect it refuses isn't followed, and a delegate that pins certificates sees the server's challenge and decides it. The README lists what Network doesn't capture: background sessions, web views, AVFoundation's streaming, Network.framework connections, stream tasks and, beyond their frames, WebSocket tasks.
- DD-194: a Network request's detail keeps its actions on one line in an iPad's drawer, at every text size: Resend stays a button (unavailable in place when the log cut the request's body short), and Copy cURL, Mock This, Edit and Resend… and Ignore Host move into a More menu beside it, as the Console's Copy All did.
- DD-186: opening a large earlier session under the Console's Previous no longer freezes the drawer: the session's lines are filtered off the main actor and the console lists its newest 2,000 that pass, with how many earlier ones it leaves out and Show Earlier to list 2,000 more, so a session of 20 MB opens without stalling the app; the toolbar no longer offers Resume under Previous, where nothing is live, and each session opens at its end.
- DD-185: on macOS, the os_log lines an app logged in the two seconds before it crashed or was killed, which the console hadn't read from its log yet, are added to that launch's Console session by the next launch, read from the system's log where the app may read it (outside the App Sandbox, run by an administrator), so a crash at launch leaves its last lines under Previous. A session's header is now written at install and names its process; a session that kept no line and missed none is deleted at the next launch. iOS, where a process reads only its own log, is unchanged.
- DD-181: a Network request row whose method, status and badges (Mocked, Conditioned, Replay) leave its path less than about twenty characters' width puts the path on a line of its own across the row, with the duration beside the status, and the badges on a line of their own too when they don't fit beside the status, rather than wrapping the path a letter or two a line in an iPad's drawer.
- DD-175: Notifications' Pending and Delivered lists no longer show every notification in full, which with dozens of them made the plugin thousands of points tall and buried the token, settings and composer: each notification is one line, its title and time, that opens to its subtitle, body, identifier, details and `userInfo`, and each list shows its newest five until Show All.
- DD-219: Hang Detector reads a stack frame whose image name has spaces (`My App`) with that name, and a frame in an Objective-C class method (`+[NSException raise:format:]`) with that method as its symbol, rather than showing the whole line or the address as the symbol.
- DD-169: Crash Reports reads a stack frame whose image name has spaces (`My App`) with that name, and a frame in an Objective-C class method (`+[NSException raise:format:]`) with that method as its symbol, rather than showing the whole line or the address as the symbol.
- DD-176: Apple frameworks' debug chatter no longer pushes the app's own lines out of the Console: it leaves out the debug and info lines of subsystems starting with `com.apple.`, keeping their notice, error and fault lines and every line of the app's own. `installConsole(sessions:includeSystemDebugLogs:)` keeps them with `includeSystemDebugLogs: true`; `installConsole(sessions:)` remains, deprecated, and forwards to it.
- DD-164: at accessibility text sizes the drawer's search results put their title and plugin name under the icon, across the row's whole width, wrapping only between words, rather than truncating or breaking a long word such as "Accessibility" mid-word; at other sizes a result keeps its one-line layout.
- DD-159: on iOS a tap outside the compact panel (an iPhone in portrait, Slide Over) closes the drawer, as one outside a sheet does: the panel leaves a strip of the app above it, and a dimmed backdrop over what it leaves of the app takes the tap. Beside a regular panel (an iPad, an iPhone in landscape) taps still reach the app.
- DD-90: Network bounds the bodies it keeps in total, not only each one, so 200 large requests no longer hold hundreds of megabytes; Console says how many older lines it dropped once it passes its capacity.
- DD-85: the Deep Link Tester reports each opened URL honestly: handled or not handled by `openURL`, opened by the system, or an error saying why the system couldn't open it, where the Mac reported Opened whatever `NSWorkspace` did. On the Mac a scheme the app declares opens in the running copy rather than another installed one, and the presets no longer include `myapp://` or the private `App-prefs:` scheme.
- DD-5: with several windows or scenes, a local plugin is listed only in the drawer of the window whose views registered it, rather than in every window's drawer; the same plugin registered from two windows stays in each until its own view leaves. On iPadOS, `toggle()` acts on the scene holding the key window when two scenes are foreground-active, and on macOS, while the app isn't active, on its frontmost window rather than the last one attached.
- DD-199: with Network installed, a request whose body is a stream reaches the server with every byte of it, rather than an empty body; a body past the body limit is sent from a temporary file, with its `Content-Length`.
- DD-204: Network's Resend no longer sends only the kept part of a request body the log cut short: Resend is unavailable and says why, and Edit and Resend shows the body as cut, with its full size, and won't send until the body is edited or removed.
- DD-71: View Inspector's view borders, click and touch ripples and alignment grid are drawn in a window of the drawer's own over each of the app's windows (on iOS, over each scene), which takes no events, rather than in the app's views: they no longer set `wantsLayer`, `borderWidth` or `borderColor` on the app's views (turning borders off used to erase the app's own borders), no longer appear in the app's own snapshots and screenshots of its windows, cover every app window rather than only the key one, leave out the drawer, keep no view alive, and follow navigation, layout and resizing (on iOS they were drawn once). Animation speed slows every app window, including ones opened later, gives each window back the exact speed it had, and its slider, now Slow Animations, reads Normal or "10× slower" rather than "10.0×".
- DD-200: on iOS, View Inspector swaps `UIWindow.sendEvent(_:)` once, in `installViewInspector()`, rather than when click indicators are first turned on.
- DD-201: in a Mac or Mac Catalyst app outside the App Sandbox, Screen Recording and Design Overlay save to `Caches/<bundle identifier>/DebugDrawer`, which App State Reset clears and no other app shares, rather than the shared `Caches/DebugDrawer`; files already in the shared folder are left there.
- DD-84: HTTP Cookies keeps a row's expanded state with its cookie (by store, name, domain and path) rather than its position, so deleting a row no longer expands the next; Delete All asks in place first and deletes only the cookies the filter shows, and the count and Copy follow the filter.

## [0.1.2] - 2026-11-17

### Added

- DD-30: Analytics plugin: the analytics events an app records, live, with search, detail and JSON export.
- DD-31: Database Browser plugin: browses the app's SQLite, Core Data and SwiftData stores read-only.
- DD-32: Localization plugin: pseudo-localizes strings, shows keys, and lists keys missing for a language.
- DD-33: Screen Recording plugin: records the app's screen without the drawer, its HUD or toasts.
- DD-34: Design Overlay plugin: lays a mockup over the running app.
- DD-35: Color Vision plugin: simulates protanopia, deuteranopia, tritanopia and grayscale.
- DD-36: App State Reset plugin: clears the app's state in one place.
- DD-37: Network mocks answer matching requests from rules.
- DD-38: Network conditions per host: latency, bandwidth caps and injected failures.
- DD-39: Network replay of a captured request, as it was or edited.
- DD-40: Network HAR 1.2 export (redacted) and import.
- DD-42: Network captures WebSocket traffic.
- DD-43: Network keeps captured sessions on disk and shows earlier ones as Previous.
- DD-44: Network hides hosts on an ignore list and shows GraphQL operation names.
- DD-45: Console keeps its lines on disk and shows earlier launches as Previous.
- DD-46: Console shows subsystem and category, mutes them, searches by regular expression and limits to a time range.
- DD-47: Console takes lines from an app's own logger (swift-log, CocoaLumberjack) through `ConsoleLogSink`, a no-op in release, and shows, searches and keeps their key/value metadata (`LogLine.metadata`, `LogLine.Source.sink`).
- DD-48: File Browser shows Documents, Library, tmp, the app bundle and app groups, with previews, sizes, dates and import.
- DD-49: UserDefaults shows app group suites, adds and edits keys of every property list type, and follows the app's writes.
- DD-50: Keychain filters by access group, shows every attribute, adds and edits generic passwords, and lists certificates and keys.
- DD-51: Location plays a GPX route at 1x, 2x, 5x or 10x.
- DD-52: Deep Link Tester continues universal links and user activities, with a history of its own.
- DD-53: App Info shows the build's commit, branch and CI number, the provisioning profile and the entitlements.
- DD-54: Performance lists threads by CPU and, on iOS, posts a simulated memory warning.
- DD-56: a CI workflow, started by hand, runs the Bazel and SwiftPM tests on macOS and an iOS simulator.
- DD-58: core's public API is documented, with a DocC catalog, and `just docs` fails on an undocumented symbol.
- DD-59: this changelog; `just deploy` refuses a version it has no entry for, and an API break unless the bump is major or `allow-breaking` is given.
- DD-79: `DebugDrawerEmptyState`, the drawer's empty state for a plugin with nothing to list yet.

### Changed

- DD-48, DD-49: `FileBrowser.install(appGroups:)` and `UserDefaultsBrowser.install(suites:)` replace
  `installFileBrowser()`, `installUserDefaults()` and the two plugins' public `init()`.
- DD-53: the bug report's app-info.json carries the build details; `installAppInfo()` takes `buildMetadata:`.
- `installNetwork`, `installConsole` and `installDeepLink` take new parameters with defaults, and
  `DebugDrawerReport.Kind` gains `movie`.
- DD-70: View Inspector counts renders only for views an app tracks with `.trackRenders(_:)`: each
  evaluation of the body that applies it, listed by name, busiest first. It no longer swizzles
  `NSView` or `UIView` to guess at every view, and Flash Renders outlines a tracked view through a
  SwiftUI overlay instead of adding views to the window.
- DD-61: every public API compiles in release, where it does nothing: `DebugDrawer.shared`, the
  plugins' `install*()` calls and types, their stores, `.trackRenders()`, `RedactedText` and
  `debugDrawerCopyToClipboard(_:)` no longer need `#if DEBUG`, and
  `just deploy` builds the example apps optimized and checks every public symbol exists in release.
- DD-72: Disk I/O records `FileManager`'s URL methods, copies, moves and folder creation, `NSData`'s
  file reads and writes and `FileHandle`'s Objective-C reads and writes, as well as creates
  (`IOEvent.Operation.create`, and the new `copy` and `move`) and failed calls with their error
  (`IOEvent.error`); totals (`DiskIOStore.totals`, `DiskIOTotals`) count every call since Clear;
  calls reach the main actor in batches; the drawer's own file work is left out, and a plugin marks
  its own with `DebugDrawerActivity.isDrawerWork`; disk space is read off the main thread.
- DD-73: the drawer opens in a window of its own, above the app's sheets and alerts: a child panel
  beside the window on macOS, an overlay window per scene on iOS. It is 316 points wide, or the
  full width at compact widths. A plugin chosen from its header, the jump bar or search shows alone
  at full height with a way back. `DebugDrawer.attach(to:)` attaches a window or scene the app
  hosts itself, and `.debugDrawer()` attaches its own; `.debugDrawer()` no longer animates the
  app's content.
- DD-62: Network forwards every request through one shared session, no longer keeps intercepted
  requests alive, and records at most `bodyLimit` bytes of each response body (1 MiB by default,
  `installNetwork(bodyLimit:)`), with `NetworkEntry.responseBodySize` and
  `isResponseBodyTruncated`.
- DD-75: Performance shows a blocked main thread as dropped frames and a lower frame rate, reads the
  real memory footprint and its lifetime peak, and Performance and Energy sample only while their
  view or the HUD readout is on screen.
- DD-78: UserDefaults lists the app's persistent domain, keys like `CountryCode` and
  `NSFWFilterEnabled` included; registered, launch-argument and global keys show under Show Other
  Domains, read-only with their source; an edited integer stays an integer and a real a real.
- DD-83: the README and doc comments describe each plugin as it behaves, say which plugins build
  on which platforms, and what each plugin needs from the app.

### Removed

- DD-64: core API no shipped plugin or example app used: `AsyncPluginView`, `OnDemandPluginView`,
  `debugDrawerCopyImageToClipboard(_:)`, `PlatformColor`, `PlatformFont`, `debugDrawerViewTag` and
  `debugDrawerOverlayIdentifier`.
- DD-64: View Inspector's unreachable measure and inspect tool (`InspectorToolController`) and its
  3D view hierarchy, which no control in the drawer opened.
- DD-70: View Inspector's `RenderTracker` (with `RenderTracker.Entry`, `isEnabled`,
  `showOverlays`, `renderCounts`, `lastRenderTimes`, `recordRender(_:)`, `reset()`, `sortedEntries`
  and `totalRenders`) and `RenderTrackingModifier`; `.trackRenders(_:)` is the API that stays.

### Fixed

- DD-177: taps beside the open drawer reach the host app again.
- DD-179: a row's icon sits beside its title when its accessory is a Toggle, Slider or Stepper.
- DD-182: the Network snapshot tests of hosted text fields no longer fail at random.
- DD-187: the Deep Link Tester's userInfo rows fit an iPad's drawer at every text size.
- DD-79: File Browser lists the app's own folders before they exist, says when they are empty, shows a refused delete and why, and keeps the folder shown and its items' identities across a refresh.
- DD-67: Location's spoofed coordinate reaches a location manager the app started before spoofing
  was turned on, holds after a relaunch, and turning spoofing off gives the app its real updates
  back; its swizzles are installed only by `installLocation()`.
- DD-66: on macOS, a line an app prints shows whole in the Console even when the pipe delivers it
  in pieces, multi-byte characters included.
- DD-192: on macOS, each printed line reaches the Console, and Xcode's console, as soon as it is
  printed.
- DD-69: a delete the keychain refuses shows "Keychain refused" with its reason.

## [0.1.1] - 2026-11-16

### Added

- DD-28: Notifications plugin: the APNs token, notification settings, pending and delivered notifications, and a pasted payload delivered as a local notification.
- DD-29: Background Tasks plugin: the app's permitted identifiers and pending requests, scheduling and cancelling them, and the LLDB commands that simulate a launch.
- DD-172: one shared visual vocabulary in core, modeled on Xcode's developer tools, used by every plugin.

### Changed

- DD-171: `just deploy` releases origin/main and pushes only the new tag.

## [0.1.0] - 2026-11-16

### Added

- DD-6: drawer search for plugins and their actions (Cmd-K).
- DD-7: plugin categories, pinning and collapsing.
- DD-8: plugin badges and toasts while the drawer is closed.
- DD-9: the floating HUD.
- DD-10: the bug report bundle, with report contributors.
- DD-11: redaction rules for copies and exports.
- DD-12: shared views for plugins (key-value rows, copy buttons).
- DD-13: the drawer's chrome works with VoiceOver, the largest text and the keyboard.
- DD-15, DD-16, DD-17, DD-18: core builds for visionOS, tvOS, watchOS and Mac Catalyst.
- DD-20: bug reports upload to the host's own endpoint.
- DD-21: Tweaks plugin.
- DD-22: Feature Flags plugin.
- DD-23: Crash Reports plugin.
- DD-24: Hang Detector plugin.
- DD-25: Leak Detector plugin.
- DD-26: MetricKit plugin.
- DD-27: Permissions plugin.
- DD-41: Network timing breakdown from URLSessionTaskMetrics.
- DD-55: overrides for Reduce Motion, Increase Contrast, Bold Text and other accessibility settings.

### Changed

- DD-80: Screenshot captures in process, with no permission.
- DD-151: `DebugDrawerPlugin` declares `id` as a requirement, so several instances of one type can register.
- DD-160: App Info and Performance show the memory footprint, not resident size.
- DD-161: the iOS console's text scales with Dynamic Type.

### Fixed

- DD-65: Launch Time measures app launch.
- DD-68: accessibility overrides keep the host's view identity and state.
- DD-76: Energy releases thread ports and restores battery monitoring.
- DD-77: App Info's uptime and launch time come from process start.
- DD-86: Loaded Libraries lists embedded frameworks as third-party.
- DD-150: Screenshot's To Desktop falls back to a save panel in a sandboxed host.
- DD-155: the iOS drawer's header sits below the status bar.
- DD-163: the Console, Cookies and Network toolbars keep whole words at accessibility text sizes.
- DD-167: App Info names the platform the app runs on.
