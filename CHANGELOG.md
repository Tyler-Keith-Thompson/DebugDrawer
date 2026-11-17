# Changelog

Notable changes in each release, newest first, in the style of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Work lands under Unreleased; before
`just deploy`, rename that heading to the new version and date (`## [0.1.2] - 2026-11-17`), start a
new empty Unreleased above it, and commit. Deploy refuses to tag a version with no entry here, and
the entry becomes the GitHub release's notes.

## [Unreleased]

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

### Changed

- DD-48, DD-49: `FileBrowser.install(appGroups:)` and `UserDefaultsBrowser.install(suites:)` replace
  `installFileBrowser()`, `installUserDefaults()` and the two plugins' public `init()`.
- DD-53: the bug report's app-info.json carries the build details; `installAppInfo()` takes `buildMetadata:`.
- `installNetwork`, `installConsole` and `installDeepLink` take new parameters with defaults, and
  `DebugDrawerReport.Kind` gains `movie`.
- DD-189: `AsyncPluginView.reload()` is removed; it never re-ran the task.
- DD-61: every public API compiles in release, where it does nothing: `DebugDrawer.shared`, the
  plugins' `install*()` calls and types, their stores, `.trackRenders()`, `AsyncPluginView`,
  `OnDemandPluginView`, `RedactedText` and the clipboard helpers no longer need `#if DEBUG`, and
  `just deploy` builds the example apps optimized and checks every public symbol exists in release.

### Fixed

- DD-177: taps beside the open drawer reach the host app again.
- DD-179: a row's icon sits beside its title when its accessory is a Toggle, Slider or Stepper.
- DD-182: the Network snapshot tests of hosted text fields no longer fail at random.
- DD-187: the Deep Link Tester's userInfo rows fit an iPad's drawer at every text size.

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
