#!/usr/bin/env python3
"""The module graph, written once.

Package.swift, swift/Package.swift, every Sources/*/BUILD.bazel and Tests/*/BUILD.bazel, the
umbrella module, tools/performance_tests.bzl, tools/executables.bzl, tools/dynamic_libraries.bzl,
tools/test_helpers.bzl, tools/examples.bzl, tools/macros.bzl, tools/swift_version.bzl and
Benchmarks/Package.swift are generated from the tables below, so SwiftPM and Bazel cannot drift.
Run `just modules` after editing them. `//:package_swift_test` fails when Package.swift disagrees
with the Bazel graph.

Modules are named after the concept they hold, with a `Module` suffix only where the module
would otherwise share a name with its main type (`GreetingModule` would hold `Greeting`). No
catch-all modules ("Core", "Utilities").
"""

import ast
import collections
import glob
import os
import re
import sys

# The package, umbrella module and test-support module take the project's name. A package whose
# main module takes the project's name (`import DebugDrawer` is that module, not an umbrella) lists
# it in MODULES like any other, and then has no umbrella.
PROJECT = "DebugDrawer"
TEST_SUPPORT = f"{PROJECT}TestSupport"

# External packages: (identity, url, minimum version). A dependency written "identity/Product"
# in the tables below refers to a product of one of these. A version written "exact:1.2.3" pins
# that release, for a package whose later releases resolve differently on different toolchains
# (Bazel resolves on each machine with its own swift). One written "minor:0.1.3" takes patch
# releases only, for a 0.x package whose minor releases break its API. One written
# "range:603.0.0..<605.0.0" admits every release from the first version up to, not including, the
# second, for a package whose next major releases still work (swift-syntax for a macro, beside a
# package capped below its newest major). After adding one:
# `just modules`, add `swiftpkg_<identity>` (hyphens as underscores) to use_repo in MODULE.bazel,
# `just resolve`.
PACKAGES = [
    # Console: reads the unified log (os_log) of the host process.
    ("oslogclient", "https://github.com/CheekyGhost-Labs/OSLogClient", "2.0.0"),
    # View tests only: view inspection, snapshots, and the issue reporting snapshot failures go
    # through (IssueReportingTestSupport routes it to Swift Testing).
    ("viewinspector", "https://github.com/nalexn/ViewInspector", "0.10.5"),
    ("swift-snapshot-testing", "https://github.com/pointfreeco/swift-snapshot-testing", "1.19.7"),
    ("swift-custom-dump", "https://github.com/pointfreeco/swift-custom-dump", "exact:1.7.0"),
    ("xctest-dynamic-overlay", "https://github.com/pointfreeco/xctest-dynamic-overlay", "1.9.0"),
]

# Packages that only Apple platforms build (Objective-C, or wrappers of Apple frameworks), by
# identity. SwiftPM links their products on Apple platforms only and Bazel on macOS only (a
# `select`), so the same targets still build on Linux, where the code using them is left out by
# `#if canImport`. //:package_swift_test leaves their products out of its comparison.
# The view tests' packages, which need SwiftUI: Linux builds the view tests without them (empty, as
# their sources sit under `#if os(macOS)`).
APPLE_ONLY_PACKAGES = ["viewinspector", "swift-snapshot-testing", "xctest-dynamic-overlay"]

# Apple platforms an Apple-only package doesn't build for, by identity: its products are linked on
# the other Apple platforms only, and the code that uses them sits under an `#if os(...)` that
# leaves the platform out.
APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS = {
    # 0.10.5's glassEffect() inspection names GlassEffect, which visionOS 26 introduced, unguarded,
    # so it compiles only for visionOS 26 and later. The tests that inspect views are under
    # `#if !os(visionOS)`.
    "viewinspector": ["visionOS"],
    # 1.19.7's Swift Testing attachment calls Image(data:), which nothing declares for visionOS,
    # and on Mac Catalyst, where UIImage doesn't conform to Testing's AttachableAsImage,
    # AssertSnapshot.swift:648's Attachment.record(_:named:as:sourceLocation:) doesn't compile
    # (an upstream bug, unfixed as of 1.19.7, the newest release). Every snapshot test is under
    # `#if os(macOS)` or `#if os(iOS) && !targetEnvironment(macCatalyst)`.
    "swift-snapshot-testing": ["visionOS", "macCatalyst"],
}

# Test targets with nothing to run off Apple platforms (all their tests under `#if os(macOS)`), by
# name. Bazel runs them on macOS alone: elsewhere they are incompatible, so `bazel test //...` skips
# them, where a test binary that ran no tests would fail. SwiftPM still builds them, empty, on Linux.
APPLE_ONLY_TESTS = []

# Test targets that also run in the iOS simulator, by name: tests of a module every platform builds
# that holds code for UIKit alone (`#if canImport(UIKit)`). Each stays in Package.swift and keeps
# its swift_test on the Mac (and Linux), and gains `<name>Simulator`, an ios_unit_test of the same
# test library hosted by tools/test_host, which Bazel runs on macOS alone. A target that depends on
# an iOS module or a Bazel label runs in the simulator alone already and isn't listed. Needs the
# test host and .bazelrc's simulator settings, which the app type ships.
SIMULATOR_TESTS = []

# Environment variables a test target's tests read, by test target name: Bazel runs a test with
# almost none of the caller's environment, so each name listed is handed through to that target's
# runners alone (`env_inherit` on its swift_test, its Performance/ one and its simulator
# ios_unit_test), and only those targets' cached results depend on the variable's value. For an
# integration test that runs only when a variable is set, such as one naming a database the
# developer starts. `--test_env` in .bazelrc would hand it to every test instead. SwiftPM passes the
# whole environment already, so Package.swift is unchanged.
# {"GreetingsTests": ["TEST_DATABASE_URL"]}
TEST_ENVIRONMENT = {}

# The product whose macro generates mocks. A module that depends on it is compiled with the
# MOCKING condition in debug builds only (SwiftPM's debug configuration, Bazel's
# --compilation_mode=dbg), so `@Mockable` emits Mock<Protocol> types for tests and release
# builds carry none.
MOCKING = "mockable/Mockable"

# (name, group, description, dependencies)
MODULES = [
    # Core
    # The one module a release build may link (the charter's D6 and D9): UI-less, and real in every
    # build. Core depends on it for the wire format, the plugin model and the sidecar's sessions,
    # and re-exports it, so `import DebugDrawer` still sees them.
    ("DebugDrawerReceiver", "Core", "The release-build sidecar receiver: serves a sidecar app, over the app group's store, only the capabilities the host enables (feature flag and experiment overrides, log level elevation, diagnostics capture, bug reports the host triggers, environment switching among the backends the host allowlists, reading and editing the UserDefaults keys the host allowlists, or any plugin model), within sessions the sidecar opens, refusing and auditing everything else; UI-less, with no interception.", []),
    ("DebugDrawer", "Core", "The drawer: its window, the plugin protocol and registry, the views plugins are built from, and release-build stand-ins.", ["DebugDrawerReceiver"]),
    # Capabilities: a plugin's UI-free half that a release build links beside the receiver (the
    # charter's D9), real in every build, with no drawer. Each depends on the receiver alone, and its
    # plugin, named after it, depends on it and re-exports it. UI-free means no drawer and no view
    # of its own: a capability whose effect lives in SwiftUI's environment holds the modifier the
    # host applies to its root view, which only sets environment values and draws nothing, since a
    # model without it would change nothing on screen and every host would write the same one.
    # The Tweaks plugin's declarations, storage and typed accessors, and the receiver capability
    # that offers the production-safe tweaks to a sidecar.
    ("DebugDrawerTweaks", "Capabilities", "Tweak declarations, their storage and typed accessors, real in every build, and the receiver capability that lets a sidecar change the tweaks the host marked production-safe; UI-free.", ["DebugDrawerReceiver"]),
    # The Analytics plugin's sink and values, and the receiver capability that mirrors the events
    # recorded during a sidecar's session, redacted in the app.
    ("DebugDrawerAnalytics", "Capabilities", "The analytics sink (AnalyticsEvents.record) and its values, real in every build, and the receiver capability that mirrors the events recorded during a sidecar's session to it, redacted before they leave the process; UI-free.", ["DebugDrawerReceiver"]),
    # The Localization plugin's modes and pseudo-localization, and the receiver capability that
    # lets a sidecar switch the strings the host reads through it to keys or pseudo text.
    ("DebugDrawerLocalization", "Capabilities", "Localization's modes and pseudo-localization, real in every build, and the receiver capability that lets a sidecar show the keys or pseudo-localized text of the strings the host looks up through LocalizationReview, for the session; no interception, UI-free.", ["DebugDrawerReceiver"]),
    # The Accessibility plugin's production half: Dynamic Type, Increase Contrast and Reduce
    # Motion overridden from a sidecar for the session, through a modifier on the host's root view.
    ("DebugDrawerAccessibility", "Capabilities", "Dynamic Type, Increase Contrast and Reduce Motion overridden from a sidecar for the session, in every build, through the receiver capability and the environment modifier the host applies to its root view; no drawer.", ["DebugDrawerReceiver"]),
    # The MetricKit plugin's payload kinds and MXMetricManager subscriber, and the receiver
    # capability that keeps the payloads (crash diagnostics among them) for a sidecar's session.
    ("DebugDrawerMetricKit", "Capabilities", "MetricKit's payload kinds and subscriber, real in every build, and the receiver capability that keeps the payloads the app receives, crash diagnostics among them, redacted and across launches, and serves them while a sidecar's session is open; UI-free.", ["DebugDrawerReceiver"]),
    # The Network plugin's mock rules and conditioning profiles, their matcher and conditioned
    # delivery, and the receiver capability that answers a sidecar's mocks during its session,
    # through a URL protocol the host lists in its own sessions' configurations.
    ("DebugDrawerNetwork", "Capabilities", "Mock rules and conditioning profiles, real in every build, and the receiver capability that answers the requests the host's own URLSession configurations send to the hosts it allows from a sidecar's rules during a grant-holding session, through a URL protocol the host lists; nothing registered globally, UI-free.", ["DebugDrawerReceiver"]),
    # The Notifications plugin's settings vocabulary and the receiver capability that shows a
    # sidecar the app's APNs device token, push environment and notification settings during its
    # session, so an employee can aim a test push at their own device.
    ("DebugDrawerNotifications", "Capabilities", "The app's notification settings, real in every build, and the receiver capability that shows a sidecar the APNs device token the host hands it, the push environment and the notification authorization and settings, only while a session is open; read-only, UI-free.", ["DebugDrawerReceiver"]),
    # The Reset App State plugin's categories and their deletion, and the receiver capability that
    # lets a sidecar clear the categories the host allows, the keychain only on its own, as the app
    # next comes to the foreground.
    ("DebugDrawerAppStateReset", "Capabilities", "The app's state cleared by category (UserDefaults, files, caches, cookies, the URL cache, the app's own cleanup, and the keychain only where the host allows it on its own), real in every build, and the receiver capability that lists for a sidecar, within its session, what each category the host allows would clear, then clears what the employee confirmed as the app next comes to the foreground; UI-free.", ["DebugDrawerReceiver"]),
    # The Hang Detector plugin's monitor (a main run loop observer and a watcher thread that samples
    # the main thread's stack), and the receiver capability that records the stalls and the host's
    # signpost intervals for a sidecar's session.
    ("DebugDrawerHangDetector", "Capabilities", "The main-thread stall monitor (a run loop observer and a watcher thread that samples the main thread's stack), real in every build, and the receiver capability that records hitches, hangs with their main-thread stacks (addresses, image UUIDs and offsets, for a dSYM) and the signpost intervals the host marks, while a sidecar records in its session; UI-free.", ["DebugDrawerReceiver"]),
    # The App Info plugin's build metadata (the commit, branch and CI build an Info.plist or the
    # host names), and the receiver capability that shows a sidecar a read-only snapshot of the
    # app's state during its session: the build, and what else the host registers.
    ("DebugDrawerAppInfo", "Capabilities", "The build's metadata (commit, branch, CI build), real in every build, and the receiver capability that shows a sidecar, during its session, a read-only snapshot of the app's state: the version and build, and only what the host registers beside them (its flag and experiment overrides, experiment buckets, environment, a user ID hashed in the process, values of its own); UI-free.", ["DebugDrawerReceiver"]),
    # The Location plugin's coordinate, and the receiver capability that lets a sidecar spoof, for
    # its session, the locations the host reads through LocationSpoofing, telling the host as
    # spoofing starts, moves and ends. Host-fed: nothing of the plugin's swizzling is in it.
    ("DebugDrawerLocation", "Capabilities", "The coordinate the Location plugin carries, real in every build, and the high-risk receiver capability that lets a sidecar spoof, within its session, the locations the host reads through LocationSpoofing, telling the host as spoofing starts, moves and ends so its own fraud checks can react; no interception, UI-free.", ["DebugDrawerReceiver"]),
    # Plugins
    ("DebugDrawerConsolePlugin", "Plugins", "Captures os_log entries (stdout and stderr on macOS) and an app logger's lines through ConsoleLogSink, with metadata: level filter, text or regular-expression search, subsystem and category mutes, time range, auto-follow, copy, lines kept across launches.", ["DebugDrawer", "oslogclient/OSLogClient"]),
    ("DebugDrawerViewInspectorPlugin", "Plugins", "View borders by depth, alignment grid, click indicators, animation speed, render tracking, hierarchy snapshot.", ["DebugDrawer"]),
    ("DebugDrawerAccessibilityPlugin", "Plugins", "Overrides color scheme, Dynamic Type, layout direction, locale and the system accessibility settings at runtime.", ["DebugDrawer", "DebugDrawerAccessibility"]),
    ("DebugDrawerAppInfoPlugin", "Plugins", "Build (version, commit, branch, CI build), provisioning profile, entitlements, OS, memory, uptime, process, debugger, screen and reachability facts.", ["DebugDrawer", "DebugDrawerAppInfo"]),
    ("DebugDrawerUserDefaultsPlugin", "Plugins", "Browse, search, add, edit, copy and delete UserDefaults keys of the standard defaults and app group suites, values of every property-list type edited at any depth, the list following the app's writes.", ["DebugDrawer"]),
    ("DebugDrawerPerformancePlugin", "Plugins", "Live FPS, dropped frames and memory with sparkline graphs, CPU per thread, and a simulated memory warning, sampled only while shown.", ["DebugDrawer"]),
    ("DebugDrawerNetworkPlugin", "Plugins", "URLProtocol HTTP interception: requests, responses, timing, cURL export, mock responses, slow and failing networks per host, replay and edit-and-resend, HAR export and import, WebSocket frames, requests kept across launches, ignored hosts, GraphQL operation names.", ["DebugDrawer", "DebugDrawerNetwork"]),
    ("DebugDrawerKeychainPlugin", "Plugins", "Browse generic and internet passwords, certificates and keys with every attribute, filter by access group, and add, edit and delete generic passwords.", ["DebugDrawer"]),
    ("DebugDrawerScreenshotPlugin", "Plugins", "Capture the app window to a file or the clipboard.", ["DebugDrawer"]),
    ("DebugDrawerFileBrowserPlugin", "Plugins", "The app's Documents, Library, tmp, bundle and app group containers, with folder totals and dates, previews of text, JSON, property lists and images, and files imported, renamed, deleted and shared, the bundle read-only.", ["DebugDrawer"]),
    ("DebugDrawerDiskIOPlugin", "Plugins", "Tracks FileManager, NSData and FileHandle file calls, flagging main-thread I/O and failures.", ["DebugDrawer"]),
    ("DebugDrawerEnergyPlugin", "Plugins", "Battery, CPU load and thermal state, sampled only while shown.", ["DebugDrawer"]),
    ("DebugDrawerLocationPlugin", "Plugins", "Spoofs CLLocationManager coordinates: presets and custom latitude and longitude.", ["DebugDrawer", "DebugDrawerLocation"]),
    ("DebugDrawerLoadedLibrariesPlugin", "Plugins", "Every loaded image, grouped as app, third-party and system, with UUIDs and load addresses.", ["DebugDrawer"]),
    ("DebugDrawerDeepLinkPlugin", "Plugins", "Opens deep links, continues universal links and user activities, and keeps a history of them.", ["DebugDrawer"]),
    ("DebugDrawerCookiesPlugin", "Plugins", "Browse and delete HTTPCookieStorage's cookies, and WKWebView's where WebKit exists.", ["DebugDrawer"]),
    ("DebugDrawerLaunchTimePlugin", "Plugins", "Pre-main, app-init-to-first-frame and total launch time.", ["DebugDrawer"]),
    ("DebugDrawerTweaksPlugin", "Plugins", "The host's own debug settings: toggles, pickers, text fields, steppers and actions, in sections.", ["DebugDrawer", "DebugDrawerTweaks"]),
    ("DebugDrawerFeatureFlagsPlugin", "Plugins", "The app's feature flags through an adapter to its flag service: live values, local overrides that persist, search and reset.", ["DebugDrawer"]),
    ("DebugDrawerCrashReportsPlugin", "Plugins", "Uncaught exceptions and fatal signals, chained to the app's other crash handlers, shown on the next launch with a badge; MetricKit crash diagnostics too.", ["DebugDrawer"]),
    ("DebugDrawerHangDetectorPlugin", "Plugins", "Main-thread hangs over a threshold the drawer can change, each with its duration and the stack it was stuck on, a toast and a badge; MetricKit hang diagnostics too.", ["DebugDrawer", "DebugDrawerHangDetector"]),
    ("DebugDrawerLeakDetectorPlugin", "Plugins", "View controllers still alive a run-loop turn after their screen was dismissed, and opted-in classes with more live instances than allowed, listed by class with a count, a toast and a badge.", ["DebugDrawer"]),
    ("DebugDrawerMetricKitPlugin", "Plugins", "MetricKit's metric and diagnostic payloads, kept across launches and listed by date with a summary, each open as formatted JSON to copy or export; a toast and a badge for new ones.", ["DebugDrawer", "DebugDrawerMetricKit"]),
    ("DebugDrawerPermissionsPlugin", "Plugins", "Every privacy permission the app declares in its Info.plist, with its live status, a button that asks when it is undecided and one that opens Settings.", ["DebugDrawer"]),
    ("DebugDrawerNotificationsPlugin", "Plugins", "The APNs device token to copy, notification authorization and settings, pending and delivered notifications to inspect and remove, and a pasted APNs payload sent as a local notification.", ["DebugDrawer", "DebugDrawerNotifications"]),
    ("DebugDrawerBackgroundTasksPlugin", "Plugins", "The BGTaskScheduler identifiers the Info.plist permits and the pending task requests, with their kind and earliest begin date, each cancellable; a request scheduled on demand, and the LLDB commands that simulate a launch or an expiration.", ["DebugDrawer"]),
    ("DebugDrawerAnalyticsPlugin", "Plugins", "The analytics events the app records, live, newest first, with their time and properties: search by name, key or value, each open as inspector rows and JSON to copy, all exported as a JSON file.", ["DebugDrawer", "DebugDrawerAnalytics"]),
    ("DebugDrawerDatabaseBrowserPlugin", "Plugins", "The app's SQLite, Core Data and SwiftData stores, opened read-only: tables or entities with row counts, rows paged and searched in a grid, and read-only SELECT queries, copied as CSV.", ["DebugDrawer"]),
    ("DebugDrawerLocalizationPlugin", "Plugins", "Pseudo-localization and show-keys modes over the strings the app looks up through Bundle's public API, live, and the translations missing for a language, grouped by table, searched and copied as text or CSV.", ["DebugDrawer", "DebugDrawerLocalization"]),
    ("DebugDrawerScreenRecordingPlugin", "Plugins", "Records the app's windows as a QuickTime movie without the drawer, its HUD or its toasts, started and stopped from the drawer or the HUD, with optional touch indicators on iOS: the saved recordings to share or delete, and the newest in the bug report.", ["DebugDrawer"]),
    ("DebugDrawerDesignOverlayPlugin", "Plugins", "A design mockup laid over the app's content, picked from Photos or Files on iOS or a file or the pasteboard on macOS: opacity, an offset set by steppers or by dragging in Move mode, the mockup's scale, and a difference blend that shows pixel drift; touches pass through to the app.", ["DebugDrawer"]),
    ("DebugDrawerColorVisionPlugin", "Plugins", "Protanopia, deuteranopia, tritanopia and grayscale simulated live over the views marked debugColorVision(), with a color-matrix shader in linear RGB, picked in the drawer or cycled from the HUD, so meaning carried only by color shows.", ["DebugDrawer"]),
    ("DebugDrawerAppStateResetPlugin", "Plugins", "The app's state cleared as a fresh install leaves it, by category: UserDefaults, keychain items, the container's files, caches, cookies, the URL cache and the app's own cleanup, each listed with what it will delete, confirmed, then relaunched on macOS or quit elsewhere.", ["DebugDrawer", "DebugDrawerAppStateReset"]),
    # Transports
    ("DebugDrawerRemote", "Transports", "Plugin models served to a viewer on another device over the local network: an opt-in Network.framework server with Bonjour, each viewer paired with a code the device shows in its Remote Viewing plugin, and the viewer's transport and browser.", ["DebugDrawer"]),
    # Sidecar: what a company builds its employee-only sidecar app on (the charter's D6). It hosts
    # the views of the plugins it depends on, so it may depend on plugins, and a view of every
    # capability the receiver ships, so it depends on each UI-free capability module (a sidecar
    # links them all; rejected: a sidecar-view product per capability). Only an app links it: no
    # module depends on it, and a production app never does. It also depends on the network
    # transport (DebugDrawerRemote) for the device-lab relay, which serves a Mac viewer what the
    # sidecar reads within its session (DD-107): the relay belongs to the sidecar app, whose
    # person opens the session and shows the pairing code, and the production app keeps talking
    # to the app group alone.
    ("DebugDrawerSidecarKit", "Sidecar", "The kit a sidecar app is built on: the apps in the group that serve it, listed as they start and stop, a session opened and ended for one, with an optional signed grant, the Console and Network views and one for every capability the receiver ships (flags, experiments, log levels, diagnostics, tweaks, strings, accessibility, analytics, MetricKit, network mocking, bug reports, push registration, scenarios, auth, reset app state, environments, location, UserDefaults, performance and app state), and any plugin's, over the socket or the store, a bug report of them, created and sent, and a relay that serves a paired Mac viewer what the open session may read and carries its commands back, for device labs; debug builds only.", ["DebugDrawer", "DebugDrawerRemote", "DebugDrawerConsolePlugin", "DebugDrawerNetworkPlugin", "DebugDrawerAppStateReset", "DebugDrawerHangDetectorPlugin", "DebugDrawerAppInfo", "DebugDrawerLocation", "DebugDrawerTweaks", "DebugDrawerAnalytics", "DebugDrawerLocalization", "DebugDrawerAccessibility", "DebugDrawerMetricKit", "DebugDrawerNetwork", "DebugDrawerNotifications"]),
]

# Modules only iOS builds: SwiftUI views and what they draw with. Bazel builds them for the
# simulator; Package.swift, the umbrella and the docs leave them out, and a module that depends on
# one must be one too. A test target that depends on one, or on a Bazel label (`//tools/...`), runs
# in the simulator as an ios_unit_test, and Package.swift leaves it out as well.
IOS_MODULES = []
IOS_MINIMUM = "17.0"

# Platforms beyond macOS and iOS, each with its minimum and the modules that also build for it, by
# name; the rest build for macOS and iOS only, until a port adds them. A platform's name is spelled
# as `os(...)` spells it, and rules_apple's rule for it is the lowercased name (`tvos_build_test`
# in `tvos.bzl`). SwiftPM's `platforms:` covers the whole package, so Package.swift declares each
# platform (PLATFORMS) and `just build-spm` builds the listed modules' schemes for its simulator.
# Bazel builds each for the simulator through a `<platform>_build_test` beside its library, so
# `bazel build //...` (`just build`) compiles it there too. A module listed for a platform depends
# only on modules listed for it.
EXTRA_PLATFORMS = {
    # visionOS 1 shipped with iOS 17's SwiftUI.
    "visionOS": ("1.0", ["DebugDrawerReceiver", "DebugDrawerTweaks", "DebugDrawerAnalytics", "DebugDrawerLocalization", "DebugDrawerAccessibility", "DebugDrawer", "DebugDrawerAnalyticsPlugin", "DebugDrawerDatabaseBrowserPlugin", "DebugDrawerLocalizationPlugin", "DebugDrawerColorVisionPlugin", "DebugDrawerAppStateReset", "DebugDrawerAppStateResetPlugin"]),
    # tvOS 17 shipped with iOS 17's SwiftUI.
    "tvOS": ("17.0", ["DebugDrawerReceiver", "DebugDrawerTweaks", "DebugDrawerAnalytics", "DebugDrawerLocalization", "DebugDrawerAccessibility", "DebugDrawer", "DebugDrawerAnalyticsPlugin", "DebugDrawerDatabaseBrowserPlugin", "DebugDrawerLocalizationPlugin", "DebugDrawerColorVisionPlugin", "DebugDrawerAppStateReset", "DebugDrawerAppStateResetPlugin"]),
    # watchOS 10 shipped with iOS 17's SwiftUI. The sidecar kit builds there for a watch sidecar
    # (DD-106: a watch app on the same watch), without the plugins not ported there
    # (PLATFORM_CONDITIONAL_DEPENDENCIES).
    "watchOS": ("10.0", ["DebugDrawerReceiver", "DebugDrawerTweaks", "DebugDrawerAnalytics", "DebugDrawerLocalization", "DebugDrawerAccessibility", "DebugDrawer", "DebugDrawerAnalyticsPlugin", "DebugDrawerDatabaseBrowserPlugin", "DebugDrawerLocalizationPlugin", "DebugDrawerAppInfo", "DebugDrawerLocation", "DebugDrawerAppStateReset", "DebugDrawerSidecarKit"]),
}

# Dependencies a module or test target links only on the platforms that build them, by target. A
# target listed for a platform (EXTRA_PLATFORMS, TESTED_PLATFORMS) that doesn't build one of these
# builds there without it, and the code that uses it sits under `#if canImport(<dependency>)`.
# Package.swift names each as `.target(name:condition: .when(platforms:))` over the platforms that
# build it (macOS, Mac Catalyst and iOS, and each of EXTRA_PLATFORMS that lists it), and Bazel in a
# `select` on them, so the generated graphs agree on every platform. Xcode builds a package target
# with its whole dependency closure, a conditional dependency's own dependencies included, and
# filters only the edges that carry a condition, so Package.swift also links the dependencies of
# such a dependency that don't build where its dependent does (packages, and modules not listed
# for that platform) on the dependency's own platforms, which changes nothing for the dependency
# itself (closure_conditions()).
PLATFORM_CONDITIONAL_DEPENDENCIES = {
    # The kit hosts, on each platform, the plugins ported there: Console, Network and the Hang
    # Detector (whose stack demangling the kit's Performance view uses) aren't ported to watchOS,
    # where the hang monitor's thread_suspend and thread_get_state don't exist. Nor are the MetricKit,
    # network mocking and push registration capability modules, so the kit's views of those three
    # exist only where their modules build. The network transport isn't ported there either, so the
    # device-lab relay exists only where it builds.
    "DebugDrawerSidecarKit": ["DebugDrawerRemote", "DebugDrawerConsolePlugin", "DebugDrawerNetworkPlugin", "DebugDrawerHangDetectorPlugin", "DebugDrawerMetricKit", "DebugDrawerNetwork", "DebugDrawerNotifications"],
    "DebugDrawerSidecarKitTests": ["DebugDrawerRemote", "DebugDrawerConsolePlugin", "DebugDrawerNetworkPlugin", "DebugDrawerHangDetectorPlugin", "DebugDrawerMetricKit", "DebugDrawerNetwork", "DebugDrawerNotifications"],
}

# Test targets that also run in the simulator of iOS or of a platform in EXTRA_PLATFORMS, by
# platform, each testing only modules listed for it. Bazel runs each as a `<Name>_<platform>` unit
# test (`just test`), with //tools:<platform>_test_runner, in a simulator made for the run; an iOS
# one runs inside //tools/test_host. SwiftPM runs each visionOS, tvOS and watchOS one through a
# scheme of its own that holds just that test target, so no unported module builds (`just
# spm-platform-test`, which `just spm-test` runs), and every target on iOS (`just test-ios`). Tests that can't run there sit
# under an `#if` that says why.
TESTED_PLATFORMS = {
    # The data protection keychain answers only a process with an application identifier, which
    # the Mac's test runners lack (errSecMissingEntitlement), and the login keychain is the user's,
    # which no test touches. So the real keychain is exercised in the iOS simulator, inside a test
    # host whose entitlements give it a keychain of its own. UIKit presents a view controller only
    # in a window of a connected scene, which SwiftPM's runner never has, so the View Inspector's
    # tests of outlines under sheets run inside the test host too.
    "iOS": ["DebugDrawerAppStateResetPluginTests", "DebugDrawerKeychainPluginTests", "DebugDrawerViewInspectorPluginTests"],
    "visionOS": ["DebugDrawerTests"],
    "tvOS": ["DebugDrawerTests"],
    # The kit's: a watch sidecar lists the apps in its group and opens and ends their sessions.
    "watchOS": ["DebugDrawerTests", "DebugDrawerSidecarKitTests"],
}

# Apple-only packages Bazel leaves out of a TESTED_PLATFORMS run, by platform. On iOS the views are
# tested on the Mac, and the Dynamic Type snapshots, which `just test-ios` runs, find their
# references beside the test through SwiftPM's absolute #filePath, which Bazel's relative one
# can't give them in the simulator; they sit under `#if canImport(SnapshotTesting)`.
BAZEL_TESTED_PLATFORM_EXCLUDED_PACKAGES = {
    "iOS": ["viewinspector", "swift-snapshot-testing"],
}

# Modules that also build for Mac Catalyst, the iOS SDK's UIKit running in a Mac window, where
# `os(iOS)` holds alongside `targetEnvironment(macCatalyst)`. SwiftPM's `.iOS` covers it, so
# Package.swift declares nothing more, and `just build-spm` builds the listed modules' schemes for
# Mac Catalyst. Bazel has no Catalyst platform, so a `catalyst_build_test` (tools/catalyst.bzl)
# beside each library compiles it for the IOS_MINIMUM Catalyst target triple instead. A module
# listed here depends only on modules listed here, and on no C or Objective-C package, which that
# rule would still build for macOS.
CATALYST_MODULES = ["DebugDrawerReceiver", "DebugDrawerTweaks", "DebugDrawerAnalytics", "DebugDrawerLocalization", "DebugDrawerAccessibility", "DebugDrawer", "DebugDrawerAnalyticsPlugin", "DebugDrawerDatabaseBrowserPlugin", "DebugDrawerLocalizationPlugin", "DebugDrawerScreenRecordingPlugin", "DebugDrawerDesignOverlayPlugin", "DebugDrawerColorVisionPlugin", "DebugDrawerAppStateReset", "DebugDrawerAppStateResetPlugin"]

# Test targets that also run for Mac Catalyst under Bazel: a `catalyst_test` (tools/catalyst.bzl),
# `<name>_macCatalyst`, builds the target's swift_test with the CATALYST_MODULES' Catalyst triple
# and runs it on the Mac, so `just test` runs the `targetEnvironment(macCatalyst)` branches. Its
# library leaves out the Apple-only packages that don't build for Catalyst
# (APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS), and the tests that need one sit under
# `#if canImport(...)`. Its first-party dependencies must be CATALYST_MODULES, and its packages
# Swift alone, as for CATALYST_MODULES. `just spm-catalyst-test` runs every test target for
# Catalyst through SwiftPM.
CATALYST_TESTS = ["DebugDrawerTests"]

# Modules whose every public symbol must have a doc comment. Their DocC archive, and so `just docs`,
# fails on one that has none (tools/documentation_coverage.py, run by docc_archive's
# `require_documentation`). Checked against the debug build's symbol graph, which holds the drawer
# as well as the API that exists in every build.
DOCUMENTED_MODULES = ["DebugDrawerReceiver", "DebugDrawerTweaks", "DebugDrawerAnalytics", "DebugDrawerLocalization", "DebugDrawerAccessibility", "DebugDrawerMetricKit", "DebugDrawerNetwork", "DebugDrawerNotifications", "DebugDrawerAppStateReset", "DebugDrawerHangDetector", "DebugDrawerAppInfo", "DebugDrawerLocation", "DebugDrawer", "DebugDrawerSidecarKit"]

# Dynamic libraries: (name, description). Each is C sources under Sources/<name> (headers in
# include/) with no dependencies, shipped as a `.dynamic` library product in Package.swift and as
# a dylib in Bazel: a cc_import named after it, which a test or a macOS app links at launch, over a
# cc_binary, with the sources also a cc_library an app can wrap in a framework of its own. For
# code that must be its own image, loaded at launch, such as dyld interposing tuples, which dyld
# applies only there. Sources compile with DEBUG in debug builds only, so a release build can
# leave them empty. They are left out of the umbrella and the docs.
DYNAMIC_LIBRARIES = [
    ("DebugDrawerDiskIOInterposer", "The Disk I/O plugin's opt-in interposer: dyld interposing tuples for read, write, pread and pwrite, inert until unsafeInstallDiskIOWithInterposing() starts them."),
]

# Example modules, by name from MODULES: code that shows the library in use (a demo app's views, a
# sample server's routes) rather than part of it. They build and test like any module, but
# Package.swift offers no library product for them, and the umbrella and the docs leave them out,
# so neither they nor their dependencies ship in `import DebugDrawer`. Only executables, test
# targets and other example modules may depend on one.
EXAMPLE_MODULES = []

# Modules offered as products of their own but left out of the umbrella, by name from MODULES:
# ones an adopter imports on purpose rather than with `import DebugDrawer`, such as a test-support
# back end (an in-memory store for their tests). Each keeps its library product, its DocC archive
# and its place in the docs; only the generated umbrella doesn't import it.
NON_UMBRELLA_MODULES = []

# Library modules that import Swift Testing, by name from MODULES: test helpers adopters add to
# their test targets (a custom Trait, an assertion that records an Issue). Bazel finds Testing only
# on the developer search paths, which rules_swift gives testonly targets alone, so these get them
# too (`always_include_developer_search_paths`), as does their symbol graph extraction for the docs.
# Not `testonly`: their docs and anything shipped that depends on them would have to be as well.
# A module that depends on one is one too, and the umbrella leaves them out (NON_UMBRELLA_MODULES),
# so `import DebugDrawer` never needs Testing.
TESTING_MODULES = []

# Resources, by target name: a module from MODULES, a test target from TEST_TARGETS, or the
# <X>PerformanceTests target of one in PERFORMANCE_TESTS. Each is a list of (rule, path), the path
# relative to Sources/<name>, Tests/<name> or Tests/<X>/Performance (a file or a directory), and
# the rule SwiftPM's: "process" flattens the files into the bundle's root (keeping a
# localization's `.lproj`), and processes them on Apple platforms as Xcode does; "copy" keeps the
# entry whole, by its last path component. Package.swift gets `resources: [.process(path),
# .copy(path)]`, and Bazel the same `<PROJECT>_<name>.bundle` and a `Bundle.module` that finds it
# (tools/resources.bzl): in an app's or a test bundle's resources on Apple platforms, in the
# runfiles of `bazel test` and `bazel run` on macOS and Linux. So a module reads its resources
# through `Bundle.module` under either build system, and a test target its fixtures the same way
# (in its swift_test, its simulator ios_unit_test and its SwiftPM test target alike).
# Apple's privacy manifest is ("copy", "PrivacyInfo.xcprivacy"), at the bundle's root where Apple
# reads it: a module holding one must list it. Firmware modules have none: Embedded Swift has no
# Foundation and no bundles.
# {"Greetings": [("process", "Data/greetings.json"), ("copy", "PrivacyInfo.xcprivacy")],
#  "GreetingsTests": [("copy", "Fixtures")], "GreetingsPerformanceTests": [("copy", "Fixtures")]}
RESOURCES = {}

# Compiler plugins holding macros: (name, group, description, dependencies), whose dependencies
# are packages' products only (swift-syntax's). A module lists one among its dependencies to offer its
# macros: SwiftPM takes it as a dependency of a `.macro` target, Bazel as a `plugins` entry of a
# swift_compiler_plugin, which rules_swift loads for that module and the modules that depend on it
# directly. A plugin is no library: it has no product, no docs and no place in the umbrella, so the
# module that declares the macros is what adopters import. A test target lists one to test its
# expansions: SwiftPM links the plugin's module into the tests, and Bazel links `<name>Library`,
# the same sources compiled as a library in the test's package, since rules_swift builds a
# test's plugin dependency for the host and loads it as a plugin, not as a module. (In the
# plugin's own package that library's swiftmodule would collide with the plugin's.)
MACROS = []

# SwiftPM command plugins: (name, verb, description, reason), run with `swift package <verb>`.
# Each is a `.plugin` target with a product of the same name, its sources in Plugins/<name>
# (SwiftPM's default). `reason` is why the plugin writes to the package directory, which SwiftPM
# shows when asking for it (`--allow-writing-to-package-directory` grants it up front); None asks
# for no permissions. Bazel builds none of them: PackagePlugin is SwiftPM's alone, so Plugins/ holds
# no BUILD.bazel, and the docs and //:package_swift_test leave them out. Keep a plugin thin, and
# prove it by running it.
PLUGINS = []

# Executables: (name, description, dependencies). Each is an `.executableTarget` and product in
# Package.swift and a swift_binary in Bazel (`bazel run //Sources/<name>`). Keep them thin: the
# code lives in MODULES, where tests can reach it. They are left out of the umbrella and the docs.
EXECUTABLES = [
]

# Test targets. SwiftPM rejects a target with no sources, so list a target only once its directory
# holds tests. (name, dependencies)
TEST_TARGETS = [
    ("DebugDrawerReceiverTests", ["DebugDrawerReceiver", "DebugDrawer", "DebugDrawerTestSupport"]),
    ("DebugDrawerAnalyticsTests", ["DebugDrawerAnalytics", "DebugDrawerReceiver", "DebugDrawer"]),
    ("DebugDrawerLocalizationTests", ["DebugDrawerLocalization", "DebugDrawerReceiver", "DebugDrawer"]),
    ("DebugDrawerAccessibilityTests", ["DebugDrawerAccessibility", "DebugDrawerReceiver", "DebugDrawer", "viewinspector/ViewInspector"]),
    ("DebugDrawerTests", ["DebugDrawer", "DebugDrawerReceiver", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerConsolePluginTests", ["DebugDrawerConsolePlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerViewInspectorPluginTests", ["DebugDrawerViewInspectorPlugin", "DebugDrawer", "DebugDrawerInterceptionContract", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerAccessibilityPluginTests", ["DebugDrawerAccessibilityPlugin", "DebugDrawerAccessibility", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerAppInfoTests", ["DebugDrawerAppInfo", "DebugDrawerReceiver", "DebugDrawer", "DebugDrawerTestSupport"]),
    ("DebugDrawerAppInfoPluginTests", ["DebugDrawerAppInfoPlugin", "DebugDrawerAppInfo", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerUserDefaultsPluginTests", ["DebugDrawerUserDefaultsPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerPerformancePluginTests", ["DebugDrawerPerformancePlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerNetworkTests", ["DebugDrawerNetwork", "DebugDrawerReceiver", "DebugDrawer"]),
    ("DebugDrawerNetworkPluginTests", ["DebugDrawerNetworkPlugin", "DebugDrawerNetwork", "DebugDrawer", "DebugDrawerInterceptionContract", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerKeychainPluginTests", ["DebugDrawerKeychainPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerScreenshotPluginTests", ["DebugDrawerScreenshotPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerFileBrowserPluginTests", ["DebugDrawerFileBrowserPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerDiskIOPluginTests", ["DebugDrawerDiskIOPlugin", "DebugDrawer", "DebugDrawerInterceptionContract", "DebugDrawerDiskIOInterposer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerEnergyPluginTests", ["DebugDrawerEnergyPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerLaunchTimePluginTests", ["DebugDrawerLaunchTimePlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerLoadedLibrariesPluginTests", ["DebugDrawerLoadedLibrariesPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerLocationTests", ["DebugDrawerLocation", "DebugDrawerReceiver", "DebugDrawer", "DebugDrawerTestSupport"]),
    ("DebugDrawerLocationPluginTests", ["DebugDrawerLocationPlugin", "DebugDrawerLocation", "DebugDrawer", "DebugDrawerInterceptionContract", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerDeepLinkPluginTests", ["DebugDrawerDeepLinkPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerCookiesPluginTests", ["DebugDrawerCookiesPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerTweaksTests", ["DebugDrawerTweaks", "DebugDrawerReceiver", "DebugDrawer", "DebugDrawerTestSupport"]),
    ("DebugDrawerTweaksPluginTests", ["DebugDrawerTweaksPlugin", "DebugDrawerTweaks", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerFeatureFlagsPluginTests", ["DebugDrawerFeatureFlagsPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerCrashReportsPluginTests", ["DebugDrawerCrashReportsPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerHangDetectorTests", ["DebugDrawerHangDetector", "DebugDrawerReceiver", "DebugDrawer"]),
    ("DebugDrawerHangDetectorPluginTests", ["DebugDrawerHangDetectorPlugin", "DebugDrawerHangDetector", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerLeakDetectorPluginTests", ["DebugDrawerLeakDetectorPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerMetricKitTests", ["DebugDrawerMetricKit", "DebugDrawerReceiver", "DebugDrawer", "DebugDrawerTestSupport"]),
    ("DebugDrawerMetricKitPluginTests", ["DebugDrawerMetricKitPlugin", "DebugDrawerMetricKit", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerPermissionsPluginTests", ["DebugDrawerPermissionsPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerNotificationsTests", ["DebugDrawerNotifications", "DebugDrawerReceiver", "DebugDrawer", "DebugDrawerTestSupport"]),
    ("DebugDrawerNotificationsPluginTests", ["DebugDrawerNotificationsPlugin", "DebugDrawerNotifications", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerBackgroundTasksPluginTests", ["DebugDrawerBackgroundTasksPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerAnalyticsPluginTests", ["DebugDrawerAnalyticsPlugin", "DebugDrawerAnalytics", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerDatabaseBrowserPluginTests", ["DebugDrawerDatabaseBrowserPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerLocalizationPluginTests", ["DebugDrawerLocalizationPlugin", "DebugDrawerLocalization", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerScreenRecordingPluginTests", ["DebugDrawerScreenRecordingPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerDesignOverlayPluginTests", ["DebugDrawerDesignOverlayPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerColorVisionPluginTests", ["DebugDrawerColorVisionPlugin", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerAppStateResetTests", ["DebugDrawerAppStateReset", "DebugDrawerReceiver", "DebugDrawer", "DebugDrawerTestSupport"]),
    ("DebugDrawerAppStateResetPluginTests", ["DebugDrawerAppStateResetPlugin", "DebugDrawerAppStateReset", "DebugDrawer", "DebugDrawerTestSupport", "viewinspector/ViewInspector", "swift-snapshot-testing/SnapshotTesting", "xctest-dynamic-overlay/IssueReportingTestSupport"]),
    ("DebugDrawerRemoteTests", ["DebugDrawerRemote", "DebugDrawer", "DebugDrawerReceiver", "DebugDrawerNetworkPlugin", "DebugDrawerNetwork", "DebugDrawerConsolePlugin", "DebugDrawerTestSupport", "viewinspector/ViewInspector"]),
    ("DebugDrawerSidecarKitTests", ["DebugDrawerSidecarKit", "DebugDrawer", "DebugDrawerReceiver", "DebugDrawerRemote", "DebugDrawerAppInfo", "DebugDrawerLocation", "DebugDrawerAppStateReset", "DebugDrawerHangDetectorPlugin", "DebugDrawerNetworkPlugin", "DebugDrawerConsolePlugin", "DebugDrawerTweaks", "DebugDrawerAnalytics", "DebugDrawerLocalization", "DebugDrawerAccessibility", "DebugDrawerMetricKit", "DebugDrawerNetwork", "DebugDrawerNotifications", "DebugDrawerTestSupport", "viewinspector/ViewInspector"]),
]

# The modules the test-support target depends on (fixtures are usually written against the
# vocabulary module). Empty is fine.
TEST_SUPPORT_DEPENDENCIES = []

# Test helpers: (name, description, dependencies). Shared checks that several test targets run,
# where TEST_SUPPORT holds data alone. Each lives in Tests/<name>: a plain target no product names
# in Package.swift, and a testonly swift_library in Bazel visible only to the test packages, so no
# library can link one; check() fails when a module or executable lists one. A test target lists it
# among its dependencies like a module; its PERFORMANCE_TESTS target leaves it out.
TEST_HELPERS = [
    ("DebugDrawerInterceptionContract",
     "The interception contract's checks (WritingPlugins.md), which interception plugins' tests run.",
     ["DebugDrawer", "DebugDrawerTestSupport"]),
]

# Bazel test sizes above the default "small" (60 s timeout), for suites whose solo run takes more
# than about 15 s on a laptop or 30 s on a four-core CI runner, and so can pass 60 s when other
# tests load the machine. "medium" is 300 s.
TEST_SIZES = {name: "medium" for name in [
]}

# Test targets whose speed-reliant tests live in Performance/ under the target's directory: tests
# that pass only if the code is fast enough, because they bound their own wall-clock time
# (ContinuousClock) or run a large or adversarial input under a `.timeLimit` meant to catch a
# complexity regression. Each is built as a target of its own, performance_target(name), with the
# same dependencies, in the same Bazel package. `--config=release` builds and runs only those:
# every other test target and test library is tagged RELEASE_EXCLUDED_TAG, which .bazelrc filters
# out under release. Debug runs both. A `.timeLimit` that only guards a small input against a hang
# does not make a test speed-reliant. SwiftPM builds the performance targets in debug but runs
# none of them: `just spm-test-mac` skips them with swift_test_performance_skip() and the
# xcodebuild stages (`just test-ios`, `just spm-catalyst-test`) with `-skip-testing:` for each of
# performance_targets(), since a debug build beside every other test can't meet their budgets.
PERFORMANCE_TESTS = [
    "DebugDrawerAppInfoTests",
    "DebugDrawerHangDetectorPluginTests",
    "DebugDrawerHangDetectorTests",
    "DebugDrawerLeakDetectorPluginTests",
    "DebugDrawerMetricKitPluginTests",
    "DebugDrawerPermissionsPluginTests",
    "DebugDrawerNotificationsPluginTests",
    "DebugDrawerBackgroundTasksPluginTests",
    "DebugDrawerAnalyticsPluginTests",
    "DebugDrawerAnalyticsTests",
    "DebugDrawerLocalizationTests",
    "DebugDrawerMetricKitTests",
    "DebugDrawerNotificationsTests",
    "DebugDrawerDatabaseBrowserPluginTests",
    "DebugDrawerLocalizationPluginTests",
    "DebugDrawerScreenRecordingPluginTests",
    "DebugDrawerDesignOverlayPluginTests",
    "DebugDrawerColorVisionPluginTests",
    "DebugDrawerAppStateResetPluginTests",
    "DebugDrawerAppStateResetTests",
    "DebugDrawerNetworkPluginTests",
    "DebugDrawerNetworkTests",
    "DebugDrawerLocationTests",
    "DebugDrawerConsolePluginTests",
]

# Performance tests run up to their one-minute limits each, so their targets get "medium" (300 s).
PERFORMANCE_TEST_SIZE = "medium"

# The tag on each performance target's swift_test: Bazel runs an `exclusive` test alone, after
# every other action of the invocation, so a wall-clock budget is measured on an otherwise idle
# build rather than beside compiles and other tests. It changes neither caching nor where the test
# runs. Only the test gets it; its library compiles in parallel like any other.
PERFORMANCE_TEST_TAG = "exclusive"

# The tag .bazelrc's release config filters out of builds and tests (see PERFORMANCE_TESTS).
RELEASE_EXCLUDED_TAG = "debug-only"

# The tag on every test that boots a simulator (the iOS, visionOS, tvOS and watchOS runners): each
# takes the one unit of the `simulator` resource .bazelrc declares (`--local_resources=simulator=1`),
# so Bazel runs those tests one at a time, while the Mac's tests and every compile go on beside them.
# Several simulators booted at once drove the load average past 200. `exclusive` would serialize
# them too, but runs each alone, after every other action, and so in sequence with everything else.
SIMULATOR_TEST_TAG = "resources:simulator:1"

# The Benchmarks/ package's targets: (name, what it imports: library modules, or "identity/Product"
# for a product of one of PACKAGES). Its Package.swift is written from this list. Each target is
# an ordo-one/benchmark executable in Benchmarks/Benchmarks/<name>, run natively on the Mac by
# `just bench` and gated against the committed `main` baseline by `just bench-check`
# (Benchmarks/README.md). The project template's simulated (Callgrind) Bazel targets are left out:
# they measure in a Linux VM, and what these measure (URLProtocol, swizzling, stdout capture)
# builds on Apple platforms only.
BENCHMARKS = [
    ("DebugDrawerNetworkPluginBenchmarks", ["DebugDrawer", "DebugDrawerNetworkPlugin"]),
    ("DebugDrawerDiskIOPluginBenchmarks", ["DebugDrawer", "DebugDrawerDiskIOPlugin"]),
    # OSLogClient: the benchmark forces the plugin's log-store poll once an iteration.
    ("DebugDrawerConsolePluginBenchmarks", ["DebugDrawer", "DebugDrawerConsolePlugin", "oslogclient/OSLogClient"]),
    ("DebugDrawerHangDetectorBenchmarks", ["DebugDrawerHangDetector", "DebugDrawerReceiver"]),
    ("DebugDrawerLeakDetectorPluginBenchmarks", ["DebugDrawer", "DebugDrawerLeakDetectorPlugin"]),
    ("DebugDrawerNetworkBenchmarks", ["DebugDrawerNetwork", "DebugDrawerReceiver"]),
]
# The benchmark targets that reach the library's `package` declarations: the stall monitor's
# checkpoint, watcher wake, stack sampler and symbolicator, which no public API calls alone. A
# package's `package` declarations are visible only to modules compiled with its package name, so
# these targets are compiled with the library's (`-package-name`, which SwiftPM takes from the
# library's directory name). Rejected: making those types public (API added only to be measured)
# and `-enable-testing` for `@testable import` (it would change how every library module is
# optimized, in every benchmark).
PACKAGE_ACCESS_BENCHMARKS = ["DebugDrawerHangDetectorBenchmarks"]
BENCHMARK_PACKAGE = ("https://github.com/ordo-one/benchmark", "1.38.2")

# The Apple platforms, as Package.swift's `Platform` spells them: where the Apple-only packages'
# products are linked.
APPLE_PLATFORMS = ["macOS", "macCatalyst", "iOS", "tvOS", "watchOS", "visionOS"]

# Keep in step with .bazelrc's --macos_minimum_os, IOS_MINIMUM and EXTRA_PLATFORMS.
PLATFORMS = '[.macOS(.v15), .iOS(.v17), .visionOS(.v1), .tvOS(.v17), .watchOS(.v10)]'
MACOS_MINIMUM = "15.0"

# The Swift the project builds with. SWIFT is the floor: every manifest's swift-tools-version, CI's
# swift:<SWIFT> and swift-bazel:<SWIFT>-<bazel> images, the Docker image's base and the minimum the
# docs state. SWIFT_TOOLCHAIN is the swift.org release swiftly installs where Xcode's toolchain falls
# short.
# To raise the floor, change both and run `just modules`: it writes them into the generated
# manifests and replaces the previous ones in SWIFT_SITES. CI needs a swift-bazel image of the new
# version (the project template's ci-image/build.sh publishes them).
SWIFT = "6.3"
SWIFT_TOOLCHAIN = "6.3.3"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The files that name SWIFT or SWIFT_TOOLCHAIN besides the ones generated here, as globs from the
# root; each is also looked for under templates/<piece>/, where the project template keeps the
# optional pieces' files. A missing one is skipped.
SWIFT_SITES = [
    "Fuzz/Package.swift", "Explore/Package.swift", "Examples/Package.swift",
    ".github/workflows/*.yml", "Dockerfile", "justfile",
    "scripts/fuzz.py", "Explore/build.sh", "tools/embedded-swift", "tools/swift_rules.bzl",
    "README.md", "AGENTS.md", ".github/README.md", ".github/docs/*.md", "Fuzz/README.md", "Explore/README.md", "Examples/README.md",
]


def swift_version_bzl():
    return (
        '"""GENERATED by scripts/modules.py (SWIFT, SWIFT_TOOLCHAIN) — edit them there, then run `just modules`."""\n\n'
        "# The Swift versions the files in SWIFT_SITES name: the next `just modules` replaces these there\n"
        "# when scripts/modules.py declares others.\n"
        f'SWIFT = "{SWIFT}"\n'
        f'SWIFT_TOOLCHAIN = "{SWIFT_TOOLCHAIN}"\n'
    )


def recorded_swift(root):
    """The (SWIFT, SWIFT_TOOLCHAIN) that tools/swift_version.bzl under `root` records, or None."""
    path = os.path.join(root, "tools", "swift_version.bzl")
    if not os.path.isfile(path):
        return None
    with open(path) as file:
        values = dict(re.findall(r'^(SWIFT|SWIFT_TOOLCHAIN) = "([^"]*)"$', file.read(), re.MULTILINE))
    return values.get("SWIFT"), values.get("SWIFT_TOOLCHAIN")


def swift_sites(root):
    paths = set()
    for site in SWIFT_SITES:
        paths.update(glob.glob(os.path.join(root, site)))
        paths.update(glob.glob(os.path.join(root, "templates", "*", site)))
    return sorted(paths)


def replace_swift(root, old, new):
    """Replaces the versions `old` with `new`, both (SWIFT, SWIFT_TOOLCHAIN), in every file of
    SWIFT_SITES under `root`, in one pass, so a replacement is never matched again. A version matches
    only whole, never inside a longer one (1.2 isn't replaced in 1.2.3 or 11.2).

    Returns the paths it changed."""
    replacements = {o: n for o, n in zip(old, new) if o and n and o != n}
    if not replacements:
        return []
    versions = "|".join(re.escape(o) for o in sorted(replacements, key=len, reverse=True))
    pattern = re.compile(rf"(?<![\w.])(?:{versions})(?!\w|\.\d)")
    changed = []
    for path in swift_sites(root):
        with open(path) as file:
            text = file.read()
        replaced = pattern.sub(lambda match: replacements[match.group(0)], text)
        if replaced != text:
            with open(path, "w") as file:
                file.write(replaced)
            changed.append(path)
    return changed


def performance_target(name):
    """The speed-reliant target split from test target `name`: FlowsTests -> FlowsPerformanceTests."""
    return name.removesuffix("Tests") + "PerformanceTests"


def performance_targets():
    """Every speed-reliant target, in PERFORMANCE_TESTS order."""
    return [performance_target(name) for name in PERFORMANCE_TESTS]


def swift_test_performance_skip():
    """The `swift test --skip` pattern matching every test in a performance target and no other.
    SwiftPM matches it against each test's identifier, which starts with the target's module name
    and a dot (`Module.Suite/test()`, `Module.Class/test`), so it is anchored there: a suite named
    like a performance target in another target still runs."""
    return "^(" + "|".join(performance_targets()) + r")\."


def duplicate_definitions():
    """The top-level names this file assigns or defines more than once, sorted.

    A template update merges a table the template adds (`MACROS = []`) as a clean insertion even
    when the project already defines it elsewhere in the file, and the later assignment wins, so
    the check reads the source rather than the values.
    """
    with open(__file__) as file:
        tree = ast.parse(file.read())
    counts = collections.Counter()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
            counts[node.name] += 1
        elif isinstance(node, ast.Assign):
            counts.update(target.id for target in node.targets if isinstance(target, ast.Name))
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            counts[node.target.id] += 1
    return sorted(name for name, count in counts.items() if count > 1)


# Apple's privacy manifest, which a module that calls a required-reason API or collects data ships
# at the root of its resource bundle (RESOURCES).
PRIVACY_MANIFEST = "PrivacyInfo.xcprivacy"


def performance_parent(name):
    """The PERFORMANCE_TESTS target whose speed-reliant target is `name`, or None."""
    return next((test for test in PERFORMANCE_TESTS if performance_target(test) == name), None)


def resources_directory(name):
    """Where RESOURCES' paths for target `name` start: Tests/<X>/Performance for X's speed-reliant
    target, Tests/<name> for a test target, else Sources/<name>."""
    if performance_parent(name):
        return f"Tests/{performance_parent(name)}/Performance"
    return f"Tests/{name}" if name in [t[0] for t in TEST_TARGETS] else f"Sources/{name}"


def resources_target(name):
    """The name of target `name`'s module_resources call in its package's BUILD.bazel: a
    speed-reliant target's sits in its test target's package, beside that one's."""
    return "PerformanceResources" if performance_parent(name) else "Resources"


def check_resources(names):
    """RESOURCES names modules by `names`, test targets or their speed-reliant targets, each entry a
    "process" or "copy" of a path that exists under the target, none listed twice or inside
    another, a test target's none under Performance/; and a module holding a privacy manifest
    lists it."""
    tests = [t[0] for t in TEST_TARGETS]
    for name, entries in RESOURCES.items():
        if name.endswith("PerformanceTests") and name not in names + tests:
            assert performance_parent(name), \
                f"RESOURCES names {name}, but no test target in PERFORMANCE_TESTS has a speed-reliant target of that name"
        else:
            assert name in names or name in tests, f"RESOURCES names {name}, which is neither a module nor a test target"
        directory = resources_directory(name)
        paths = [path for _, path in entries]
        for rule, path in entries:
            assert rule in ("process", "copy"), f"RESOURCES gives {directory}/{path} the rule {rule!r}: use \"process\" or \"copy\""
            assert path == os.path.normpath(path) and not os.path.isabs(path) and not path.startswith(".."), \
                f"RESOURCES lists {path!r} for {name}: give a path inside {directory}, without ./, ../ or a trailing /"
            assert os.path.exists(os.path.join(ROOT, directory, path)), \
                f"RESOURCES lists {directory}/{path}, which doesn't exist"
            assert not (name in tests and (path == "Performance" or path.startswith("Performance/"))), \
                f"RESOURCES lists {directory}/{path}, in the speed-reliant tests' directory, which the test target leaves out"
            assert paths.count(path) == 1, f"RESOURCES lists {directory}/{path} more than once"
            outer = [other for other in paths if path.startswith(other + "/")]
            assert not outer, f"RESOURCES lists {directory}/{path} inside {directory}/{outer[0]}, which it lists too"
    for name in names:
        if os.path.isfile(os.path.join(ROOT, "Sources", name, PRIVACY_MANIFEST)):
            assert PRIVACY_MANIFEST in [path for _, path in RESOURCES.get(name, [])], (
                f"Sources/{name} holds a {PRIVACY_MANIFEST} that RESOURCES doesn't list, so it would ship in no bundle: "
                f"add (\"copy\", \"{PRIVACY_MANIFEST}\") to RESOURCES[\"{name}\"]")


def check():
    names = [m[0] for m in MODULES]
    # A plugin is a dependency like a module, but no list of modules below may name one.
    plugins = macro_names()
    assert len(names + plugins) == len(set(names + plugins)), "duplicate module"
    for name in APPLE_ONLY_TESTS:
        assert name in dict(TEST_TARGETS), f"APPLE_ONLY_TESTS names unknown test target {name}"
    for name in SIMULATOR_TESTS:
        assert name in dict(TEST_TARGETS), f"SIMULATOR_TESTS names unknown test target {name}"
        assert not simulator_only(name), \
            f"{name} depends on an iOS module or a Bazel label, so it runs in the simulator alone already: leave it out of SIMULATOR_TESTS"
    for name, variables in TEST_ENVIRONMENT.items():
        assert name in dict(TEST_TARGETS), f"TEST_ENVIRONMENT names unknown test target {name}"
        assert variables, f"TEST_ENVIRONMENT gives {name} no variables: list at least one, or leave {name} out"
        for variable in variables:
            assert re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", variable), \
                f"TEST_ENVIRONMENT gives {name} {variable!r}, which isn't an environment variable's name"
            assert variables.count(variable) == 1, f"TEST_ENVIRONMENT lists {variable} for {name} more than once"
    # The root BUILD.bazel leaves iOS modules out of the docs and //:package_swift_test through
    # tools/ios.bzl, which only the app type and --ios write.
    assert not IOS_MODULES, (
        "IOS_MODULES needs tools/ios.bzl, the iOS test host and the simulator settings the app type and the "
        "--ios option ship: from the project template's checkout, ./template.py add <project> --ios")
    simulator_tests = sorted(name for name, _ in TEST_TARGETS if simulator_test(name))
    if simulator_tests:
        with open(os.path.join(ROOT, ".bazelrc")) as file:
            settings = "--local_resources=simulator=" in file.read()
        assert os.path.isfile(os.path.join(ROOT, "tools", "test_host", "BUILD.bazel")) and settings, (
            f"{', '.join(simulator_tests)} run in the iOS simulator (SIMULATOR_TESTS, or a dependency on an iOS "
            "module or a Bazel label), which needs the test host (tools/test_host) and the simulator settings "
            "in .bazelrc (--ios_minimum_os, --ios_simulator_device, --ios_simulator_version, "
            "--local_resources=simulator=1) that the app type and the --ios option ship: from the project "
            "template's checkout, ./template.py add <project> --ios")
    packages = [p[0] for p in PACKAGES]
    helpers = [h[0] for h in TEST_HELPERS]
    assert len(helpers) == len(set(helpers)), "duplicate test helper"
    assert not set(helpers) & set(names + plugins + [PROJECT, TEST_SUPPORT]), "a test helper shares a module's name"
    for name, _, deps in TEST_HELPERS:
        for d in deps:
            # The test-support target is testonly too, so a helper may use its fixtures.
            assert "/" not in d and d in names + [TEST_SUPPORT], f"test helper {name} depends on {d}, which isn't a module or {TEST_SUPPORT}"
    for name, _, version in PACKAGES:
        if version.startswith("range:"):
            lower, upper = version_range(version)
            assert "..<" in version and semantic_version(lower) and semantic_version(upper), (
                f"PACKAGES gives {name} {version!r}: write a range as range:<lower>..<<upper>, two versions "
                "such as range:603.0.0..<605.0.0")
            assert semantic_version(lower) < semantic_version(upper), \
                f"PACKAGES gives {name} {version!r}, whose lower bound isn't below its upper"
    for name, deps in [(m[0], m[3]) for m in MODULES + MACROS] + [(e[0], e[2]) for e in EXECUTABLES]:
        for d in deps:
            # A test helper is testonly: only test targets link it.
            assert d not in helpers, f"{name} depends on the test helper {d}; only a test target may"
            if "/" in d:
                assert d.split("/")[0] in packages, f"{name} depends on unknown package {d}"
            else:
                assert d in names + plugins, f"{name} depends on unknown {d}"
    for name, _, _, deps in MACROS:
        assert all("/" in d for d in deps), f"the plugin {name} may depend on packages only"
    executables = [e[0] for e in EXECUTABLES]
    assert not set(executables) & set(names + plugins + [PROJECT]), "an executable shares a module's name"
    dynamic = [d[0] for d in DYNAMIC_LIBRARIES]
    assert len(dynamic) == len(set(dynamic)), "duplicate dynamic library"
    assert not set(dynamic) & set(names + plugins + executables + [PROJECT]), "a dynamic library shares a module's name"
    for name, deps in [(m[0], m[3]) for m in MODULES] + [(e[0], e[2]) for e in EXECUTABLES]:
        # A module that linked one would put its own copy into every image that links the module,
        # and a module needn't: it finds a library's functions with dlsym when the app links it.
        assert not set(deps) & set(dynamic), f"{name} depends on a dynamic library; only a test target may"
    tests = [t[0] for t in TEST_TARGETS]
    assert len(tests) == len(set(tests)), "duplicate test target"
    for name, deps in TEST_TARGETS:
        for d in deps:
            if d.startswith("//"):
                continue
            if "/" in d:
                assert d.split("/")[0] in packages, f"{name} depends on unknown package {d}"
            else:
                assert d in names + plugins + dynamic + helpers + [PROJECT, TEST_SUPPORT], f"{name} depends on unknown {d}"
        assert not (simulator_test(name) and any(is_macro(d) for d in deps)), \
            f"{name} tests a compiler plugin, which only tests on the Mac can link"
    # A command plugin shares SwiftPM's namespace of targets and products.
    taken = {**{t: "a test target" for t in tests + [TEST_SUPPORT]}, **{e: "an executable" for e in executables},
             **{m: "a macro" for m in plugins}, **{d: "a dynamic library" for d in dynamic},
             **{h: "a test helper" for h in helpers}, **{m: "a module" for m in names + [PROJECT]}}
    commands = [p[0] for p in PLUGINS]
    assert len(commands) == len(set(commands)), "duplicate command plugin"
    verbs = [p[1] for p in PLUGINS]
    assert len(verbs) == len(set(verbs)), "two command plugins share a verb"
    for name, _, _, _ in PLUGINS:
        assert name not in taken, f"the command plugin {name} has the name of {taken.get(name)}"
        assert glob.glob(os.path.join(ROOT, "Plugins", name, "**", "*.swift"), recursive=True), \
            f"the command plugin {name} has no Swift sources in Plugins/{name}"
    for name in PERFORMANCE_TESTS:
        assert name in tests, f"PERFORMANCE_TESTS names unknown test target {name}"
        assert not simulator_test(name), f"{name} runs in the simulator, which PERFORMANCE_TESTS doesn't support"
    for name in IOS_MODULES:
        assert name in names, f"IOS_MODULES names unknown module {name}"
    for platform, (minimum, modules) in EXTRA_PLATFORMS.items():
        declared = f".{platform}(.v{minimum.split('.')[0]})"
        assert declared in PLATFORMS, f"PLATFORMS must declare {declared}, as EXTRA_PLATFORMS does"
        for name in modules:
            assert name in names, f"EXTRA_PLATFORMS[{platform!r}] names unknown module {name}"
            assert name not in IOS_MODULES, f"{name} is in IOS_MODULES, so it can't build for {platform}"
            for d in dict((m[0], m[3]) for m in MODULES)[name]:
                assert "/" in d or d in modules or d in PLATFORM_CONDITIONAL_DEPENDENCIES.get(name, []), \
                    f"{name} builds for {platform}, so its dependency {d} must be listed for it, or in PLATFORM_CONDITIONAL_DEPENDENCIES"
    for name, deps in BENCHMARKS:
        for d in deps:
            if "/" in d:
                assert d.split("/")[0] in packages, f"benchmark {name} imports unknown package {d}"
            else:
                assert d in names and d not in IOS_MODULES, f"benchmark {name} imports {d}, which isn't a module Package.swift declares"
    for name in PACKAGE_ACCESS_BENCHMARKS:
        assert name in dict(BENCHMARKS), f"PACKAGE_ACCESS_BENCHMARKS names unknown benchmark {name}"
    for platform, targets in TESTED_PLATFORMS.items():
        assert platform == "iOS" or platform in EXTRA_PLATFORMS, f"TESTED_PLATFORMS names {platform}, which EXTRA_PLATFORMS doesn't"
        for name in targets:
            assert name in tests, f"TESTED_PLATFORMS[{platform!r}] names unknown test target {name}"
            assert not simulator_test(name), f"{name} runs in the iOS simulator already, so it can't run on {platform}"
            for d in dict(TEST_TARGETS)[name]:
                # The test-support target has no platform list: it builds wherever a test does.
                assert "/" in d or platform == "iOS" or d == TEST_SUPPORT or d in EXTRA_PLATFORMS[platform][1] or d in PLATFORM_CONDITIONAL_DEPENDENCIES.get(name, []), \
                    f"{name} runs on {platform}, so its dependency {d} must be listed for it in EXTRA_PLATFORMS, or in PLATFORM_CONDITIONAL_DEPENDENCIES"
    all_deps = dict([(m[0], m[3]) for m in MODULES] + TEST_TARGETS)
    for name, conditional in PLATFORM_CONDITIONAL_DEPENDENCIES.items():
        assert name in all_deps, f"PLATFORM_CONDITIONAL_DEPENDENCIES names unknown target {name}"
        assert name not in PERFORMANCE_TESTS, f"{name} is in PERFORMANCE_TESTS, which PLATFORM_CONDITIONAL_DEPENDENCIES doesn't support"
        for d in conditional:
            assert d in all_deps[name], f"PLATFORM_CONDITIONAL_DEPENDENCIES lists {d} for {name}, which doesn't depend on it"
            assert d in names and d not in IOS_MODULES, f"PLATFORM_CONDITIONAL_DEPENDENCIES lists {d} for {name}, which isn't a module every Apple platform's Package.swift declares"
            assert any(name in targets_on(p) and d not in EXTRA_PLATFORMS[p][1] for p in EXTRA_PLATFORMS), \
                f"PLATFORM_CONDITIONAL_DEPENDENCIES lists {d} for {name}, which builds wherever {name} does"
    for platform, packages in BAZEL_TESTED_PLATFORM_EXCLUDED_PACKAGES.items():
        assert platform in TESTED_PLATFORMS, f"BAZEL_TESTED_PLATFORM_EXCLUDED_PACKAGES names {platform}, which TESTED_PLATFORMS doesn't"
        for package in packages:
            assert package in APPLE_ONLY_PACKAGES, f"BAZEL_TESTED_PLATFORM_EXCLUDED_PACKAGES names {package}, which isn't Apple-only"
    for package, platforms in APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS.items():
        assert package in APPLE_ONLY_PACKAGES, f"APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS names {package}, which isn't Apple-only"
        for platform in platforms:
            assert platform in APPLE_PLATFORMS, f"APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS names unknown platform {platform}"
    for name in CATALYST_MODULES:
        assert name in names, f"CATALYST_MODULES names unknown module {name}"
        assert name not in IOS_MODULES, f"{name} is in IOS_MODULES, so it can't build for Mac Catalyst"
        for d in dict((m[0], m[3]) for m in MODULES)[name]:
            assert "/" not in d and d in CATALYST_MODULES, f"{name} builds for Mac Catalyst, so its dependency {d} must be listed for it"
    for name in CATALYST_TESTS:
        assert name in tests, f"CATALYST_TESTS names unknown test target {name}"
        assert not simulator_test(name), f"{name} runs in the iOS simulator, so it can't run for Mac Catalyst"
        assert name not in PERFORMANCE_TESTS, f"{name} is in PERFORMANCE_TESTS, which CATALYST_TESTS doesn't support"
        for d in dict(TEST_TARGETS)[name]:
            assert "/" in d or d == TEST_SUPPORT or d in CATALYST_MODULES, f"{name} runs for Mac Catalyst, so its dependency {d} must be in CATALYST_MODULES"
    # The charter's vertical modules: a plugin depends on core and Apple's frameworks alone, so an
    # app links only the tools it picks. Console's OSLogClient is the one package allowed.
    # A capability (a plugin's release-build half) depends on the receiver alone, and only its own
    # plugin may depend on it.
    capabilities = [m[0] for m in MODULES if m[1] == "Capabilities"]
    # The production app opens no network listener (DD-107): the network transport, the one module
    # that imports Network.framework, is never in what a release build links, so a sidecar relays to
    # a Mac viewer and the production app talks to the app group alone.
    module_deps = dict((m[0], m[3]) for m in MODULES)
    def closure(name):
        found, pending = set(), [name]
        while pending:
            for d in module_deps.get(pending.pop(), []):
                if d in module_deps and d not in found:
                    found.add(d)
                    pending.append(d)
        return found
    for name in ["DebugDrawerReceiver"] + capabilities:
        assert "DebugDrawerRemote" not in closure(name), f"{name} links into release builds, so it can't depend on DebugDrawerRemote"
    for name, group, _, deps in MODULES:
        if group in ("Plugins", "Transports"):
            allowed = ["DebugDrawer"] + (["oslogclient/OSLogClient"] if name == "DebugDrawerConsolePlugin" else [])
            allowed += [c for c in capabilities if name == c + "Plugin"]
            assert set(deps) <= set(allowed), f"{name} is a plugin or transport, so it depends on DebugDrawer (and its own capability) alone, not {sorted(set(deps) - set(allowed))}"
        if group == "Capabilities":
            assert deps == ["DebugDrawerReceiver"], f"{name} is a capability, so it depends on DebugDrawerReceiver alone, not {deps}"
            assert name + "Plugin" in names, f"{name} is a capability, so a plugin {name}Plugin holds its drawer half"
    # What a release build links (the charter's N1 and D6): the receiver and the capabilities. The
    # receiver depends on nothing, so a production app can't link the drawer's report uploader
    # (DebugDrawerReportUploader, in DebugDrawer) or anything else that sends; a sidecar uploads.
    assert dict((m[0], m[3]) for m in MODULES)["DebugDrawerReceiver"] == [], "DebugDrawerReceiver links into release builds, so it depends on nothing"
    # The charter allows no macro package in any library target, and a MACROS row would pull
    # swift-syntax into whichever module lists it.
    assert not MACROS, "the charter allows no macro package in a library target, so MACROS stays empty"
    for name in EXAMPLE_MODULES:
        assert name in names, f"EXAMPLE_MODULES names unknown module {name}"
    for name in NON_UMBRELLA_MODULES:
        assert name in names, f"NON_UMBRELLA_MODULES names unknown module {name}"
        assert name != PROJECT and umbrella(), f"NON_UMBRELLA_MODULES lists {name}, but the package has no umbrella to leave it out of"
        assert name not in EXAMPLE_MODULES, f"{name} is an example module, which the umbrella already leaves out"
        assert name not in IOS_MODULES, f"{name} is an iOS module, which the umbrella already leaves out"
    for name, _, _, deps in MODULES:
        if name not in EXAMPLE_MODULES:
            for d in deps:
                assert d not in EXAMPLE_MODULES, f"{name} depends on the example module {d}, so it must be in EXAMPLE_MODULES"
    for name, _, _, deps in MODULES:
        if name not in IOS_MODULES:
            for d in deps:
                assert d not in IOS_MODULES, f"{name} depends on the iOS module {d}, so it must be in IOS_MODULES"
    for name in TESTING_MODULES:
        assert name in names, f"TESTING_MODULES names unknown module {name}"
        assert name not in IOS_MODULES, f"{name} is an iOS module, which the app ships, so it can't import Testing"
        assert not umbrella() or name in NON_UMBRELLA_MODULES + EXAMPLE_MODULES, \
            f"{name} imports Testing, so the umbrella must leave it out: list it in NON_UMBRELLA_MODULES"
    for name, _, _, deps in MODULES:
        if name not in TESTING_MODULES:
            for d in deps:
                assert d not in TESTING_MODULES, f"{name} depends on {d}, which imports Testing, so it must be in TESTING_MODULES"
    for name, _, deps in EXECUTABLES:
        for d in deps:
            assert d not in TESTING_MODULES, f"the executable {name} depends on {d}, which imports Testing, a test-only library"
    check_resources(names)


def targets_on(platform):
    """The modules EXTRA_PLATFORMS lists for `platform` and the test targets TESTED_PLATFORMS runs there."""
    return EXTRA_PLATFORMS[platform][1] + TESTED_PLATFORMS.get(platform, [])


def module_platforms(name):
    """The platforms, as Package.swift's `Platform` spells them, that build module `name`: macOS, Mac
    Catalyst and iOS, and each of EXTRA_PLATFORMS that lists it."""
    return [p for p in APPLE_PLATFORMS if p in ("macOS", "macCatalyst", "iOS") or name in EXTRA_PLATFORMS.get(p, ("", []))[1]]


def platforms_variable(name):
    """The Package.swift constant holding module `name`'s platforms: DebugDrawerConsolePlugin ->
    consolePluginPlatforms."""
    short = name.removeprefix(PROJECT) or name
    return short[0].lower() + short[1:] + "Platforms"


def conditional(target, d):
    """Whether `target` links dependency `d` only on the platforms that build it."""
    return d in PLATFORM_CONDITIONAL_DEPENDENCIES.get(target, [])


def closure_conditions():
    """The (module, dependency) edges inside PLATFORM_CONDITIONAL_DEPENDENCIES' closures that
    Package.swift links on the module's own platforms: a dependency that is a package (not an
    Apple-only one, which is conditioned already), or a module that doesn't build on every platform
    the conditioning target does. Without them Xcode would build, say, the Console plugin's
    OSLogClient for the sidecar kit on watchOS, though it leaves out the plugin itself."""
    deps = dict((m[0], m[3]) for m in MODULES)
    edges = set()
    for target, conditional_deps in PLATFORM_CONDITIONAL_DEPENDENCIES.items():
        # Where the target builds: a module's platforms, or a test target's (TESTED_PLATFORMS).
        wanted = set(module_platforms(target) if target in deps else
                     ["macOS", "macCatalyst", "iOS"] + [p for p, targets in TESTED_PLATFORMS.items() if target in targets])
        pending = list(conditional_deps)
        seen = set()
        while pending:
            module = pending.pop()
            if module in seen:
                continue
            seen.add(module)
            for d in deps[module]:
                if "/" in d:
                    if not apple_only(d):
                        edges.add((module, d))
                elif not wanted <= set(module_platforms(d)):
                    edges.add((module, d))
                    pending.append(d)
    return edges


def snapshot_name_clashes(root, name):
    """The snapshot references of test target `name` (under `root`/Tests) that share a base name.

    rules_xcodeproj copies a test target's references into one flat bundle, so two with the same
    base name (`editor-colorScheme.light.png` under two suites) make `bazel run //:xcodeproj`
    fail with conflicting actions. Returns one sorted list of paths relative to `root` per shared
    name, sorted by name; empty when every name is unique.
    """
    paths = {}
    for parent, _, files in os.walk(os.path.join(root, "Tests", name, "__Snapshots__")):
        for file in files:
            paths.setdefault(file, []).append(os.path.relpath(os.path.join(parent, file), root))
    return [sorted(paths[file]) for file in sorted(paths) if len(paths[file]) > 1]


def macro_names():
    """The compiler plugins' names (MACROS)."""
    return [m[0] for m in MACROS]


def is_macro(d):
    """Whether dependency `d` names a compiler plugin (MACROS)."""
    return d in macro_names()


def simulator_only(name):
    """Whether test target `name` runs in the iOS simulator alone: it depends on an iOS module or a Bazel
    label, so Package.swift leaves it out."""
    deps = dict(TEST_TARGETS)[name]
    return any(d in IOS_MODULES or d.startswith("//") for d in deps)


def simulator_test(name):
    """Whether test target `name` runs in the iOS simulator: alone, or on the Mac too (SIMULATOR_TESTS)."""
    return name in SIMULATOR_TESTS or simulator_only(name)


def simulator_label(name):
    """The ios_unit_test that runs simulator test target `name`: the package's own target, or
    `<name>Simulator` beside the Mac tests for one in SIMULATOR_TESTS."""
    return f"//Tests/{name}" + (f":{name}Simulator" if name in SIMULATOR_TESTS else "")


def spm_dep(d, target=None):
    """Dependency `d` of `target` as a Package.swift target's dependencies list it."""
    if conditional(target, d):
        return f'.target(name: "{d}", condition: .when(platforms: {platforms_variable(d)}))'
    if (target, d) in closure_conditions():
        if "/" in d:
            package, product = d.split("/")
            return f'.product(name: "{product}", package: "{package}", condition: .when(platforms: {platforms_variable(target)}))'
        return f'.target(name: "{d}", condition: .when(platforms: {platforms_variable(target)}))'
    if "/" in d:
        package, product = d.split("/")
        excluded = APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS.get(package, [])
        platforms = "applePlatforms" if not excluded else "[" + ", ".join(f".{p}" for p in APPLE_PLATFORMS if p not in excluded) + "]"
        condition = f", condition: .when(platforms: {platforms})" if package in APPLE_ONLY_PACKAGES else ""
        return f'.product(name: "{product}", package: "{package}"{condition})'
    return f'"{d}"'


def requirement(version):
    """A package's version requirement in a manifest: `from:` the minimum, `exact:` a pinned release,
    `.upToNextMinor(from:)` for `minor:`, patch releases only, or a half-open range
    (`"603.0.0"..<"605.0.0"`) for `range:603.0.0..<605.0.0`. check() refuses a malformed range."""
    if version.startswith("exact:"):
        return f'exact: "{version.removeprefix("exact:")}"'
    if version.startswith("minor:"):
        return f'.upToNextMinor(from: "{version.removeprefix("minor:")}")'
    if version.startswith("range:"):
        lower, upper = version_range(version)
        return f'"{lower}"..<"{upper}"'
    return f'from: "{version}"'


def version_range(version):
    """The (lower, upper) bounds of a `range:<lower>..<<upper>` version, as written."""
    lower, _, upper = version.removeprefix("range:").partition("..<")
    return lower, upper


def semantic_version(text):
    """`text`'s (major, minor, patch) when it is a semantic version (a pre-release or build suffix
    allowed), else None."""
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", text)
    return tuple(int(part) for part in match.groups()) if match else None


def umbrella():
    """Whether the package has a generated umbrella module: unless MODULES lists the project's name."""
    return PROJECT not in [m[0] for m in MODULES]


def package_modules():
    """MODULES that Package.swift declares: every one but the iOS modules."""
    return [m for m in MODULES if m[0] not in IOS_MODULES]


def library_modules():
    """MODULES that the package offers as products and the umbrella imports: every one Package.swift
    declares but the example modules."""
    return [m for m in package_modules() if m[0] not in EXAMPLE_MODULES]


def umbrella_modules():
    """MODULES the generated umbrella imports: every library product but NON_UMBRELLA_MODULES."""
    return [m for m in library_modules() if m[0] not in NON_UMBRELLA_MODULES]


def package_tests():
    """TEST_TARGETS that Package.swift declares: every one but those run in the simulator alone."""
    return [t for t in TEST_TARGETS if not simulator_only(t[0])]


def package_dependencies():
    """PACKAGES that Package.swift declares: those a target it declares uses, or every one when no
    module is iOS-only. A package only iOS modules and simulator tests use is Bazel's alone
    (swift/Package.swift), as SwiftPM warns about a dependency no target uses."""
    if not IOS_MODULES:
        return PACKAGES
    used = {d.split("/")[0] for _, deps in [(m[0], m[3]) for m in package_modules() + MACROS] + [(e[0], e[2]) for e in EXECUTABLES] + package_tests()
            for d in deps if "/" in d and not d.startswith("//")}
    return [p for p in PACKAGES if p[0] in used]


def apple_only(d):
    return "/" in d and d.split("/")[0] in APPLE_ONLY_PACKAGES


def bazel_deps(deps, platforms=(), target=None, testing=False, ios=False):
    """A `deps` attribute, or nothing when there are none; Apple-only products sit in a `select` on
    macOS and on each of `platforms` (EXTRA_PLATFORMS names, or macCatalyst) that builds them, but
    for a target only iOS builds (`ios`), which lists them with the rest; and `target`'s
    PLATFORM_CONDITIONAL_DEPENDENCIES in one on the platforms that build each.
    A compiler plugin (MACROS) goes in a `plugins` attribute instead, but for a test library
    (`testing`), which links the plugin's `<name>Library` in its own package (see MACROS)."""
    if testing:
        return _bazel_deps([f":{d}Library" if is_macro(d) else d for d in deps], platforms, target, ios)
    plugins = "".join(f'        "{bazel_label(d)}",\n' for d in deps if is_macro(d))
    return (_bazel_deps([d for d in deps if not is_macro(d)], platforms, target)
            + (f"    plugins = [\n{plugins}    ],\n" if plugins else ""))


# The project keeps its per-platform select keys (macOS plus each listed platform) rather than the
# template's every-Apple-OS select, because APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS must leave
# ViewInspector and SnapshotTesting out of visionOS. Only test targets list Apple-only packages
# today; a library module that lists one would get it on macOS alone.
def _bazel_deps(deps, platforms=(), target=None, ios=False):
    if not deps:
        return ""
    listed = "".join(f'        "{bazel_label(d)}",\n' for d in deps if (ios or not apple_only(d)) and not conditional(target, d))
    text = f"    deps = [\n{listed}    ]"
    conditional_branches = ""
    # Catalyst is a macOS configuration (tools/catalyst.bzl), so the macOS branch covers it.
    for platform in ["macOS", "iOS", *EXTRA_PLATFORMS]:
        linked = "".join(f'            "{bazel_label(d)}",\n' for d in deps if conditional(target, d) and platform in module_platforms(d))
        if linked:
            conditional_branches += f'        "@platforms//os:{platform.lower()}": [\n{linked}        ],\n'
    if conditional_branches:
        text += (
            " + select({\n"
            "        # Linked where they build (PLATFORM_CONDITIONAL_DEPENDENCIES in scripts/modules.py).\n"
            f"{conditional_branches}"
            '        "//conditions:default": [],\n'
            "    })"
        )
    branches = ""
    # Every Apple-only product is listed above for a target only iOS builds.
    for platform in [] if ios else ["macOS", *platforms]:
        apple = "".join(f'            "{bazel_label(d)}",\n' for d in deps
                        if apple_only(d) and platform not in APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS.get(d.split("/")[0], [])
                        and d.split("/")[0] not in BAZEL_TESTED_PLATFORM_EXCLUDED_PACKAGES.get(platform, []))
        if apple:
            # Catalyst is a macOS configuration (tools/catalyst.bzl), told apart by a config setting.
            key = "//tools:catalyst" if platform == "macCatalyst" else f"@platforms//os:{platform.lower()}"
            branches += f'        "{key}": [\n{apple}        ],\n'
    if branches:
        text += (
            " + select({\n"
            "        # Apple-only packages (APPLE_ONLY_PACKAGES in scripts/modules.py).\n"
            f"{branches}"
            '        "//conditions:default": [],\n'
            "    })"
        )
    return text + ",\n"


def bazel_label(d):
    if d.startswith("//") or d.startswith(":"):
        return d
    if "/" in d:
        package, product = d.split("/")
        return f"@swiftpkg_{package.replace('-', '_')}//:{product}"
    if d == TEST_SUPPORT or d in test_helpers():
        return f"//Tests/{d}"
    return f"//Sources/{d}"


def test_helpers():
    """The names of TEST_HELPERS."""
    return [h[0] for h in TEST_HELPERS]


def performance_dependencies(deps):
    """A PERFORMANCE_TESTS target's dependencies: its test target's, without the test helpers."""
    return [d for d in deps if d not in test_helpers()]


def excluded(path):
    """Non-source files SwiftPM would otherwise warn about, for the target at `path`. Shaders/ holds
    Metal sources that ship precompiled (tools/metallibs.py), which SwiftPM would otherwise compile."""
    return [f for f in ("BUILD.bazel", "README.md", "Performance", "__Snapshots__", "Shaders") if os.path.exists(os.path.join(ROOT, path, f))]


def swift_string(text):
    """`text` as a Swift string literal."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def resources_arg(name):
    """Target `name`'s `resources:` argument in Package.swift (RESOURCES), or nothing."""
    entries = RESOURCES.get(name, [])
    if not entries:
        return ""
    return ", resources: [" + ", ".join(f".{rule}({swift_string(path)})" for rule, path in entries) + "]"


def resources_bazel(name):
    """Target `name`'s resources in its BUILD.bazel (RESOURCES): the load, the swift_library's `srcs`
    and `data`, and the module_resources call (tools/resources.bzl). Without resources, the plain
    `srcs` and nothing else."""
    entries = RESOURCES.get(name, [])
    if not entries:
        return "", '    srcs = glob(["**/*.swift"]),\n', "", ""
    what = ("speed-reliant tests' fixtures" if performance_parent(name)
            else "tests' fixtures" if resources_directory(name).startswith("Tests/") else "module's resources")
    target = resources_target(name)
    # The speed-reliant target's SwiftPM path is the package's Performance/, which its entries are
    # relative to.
    directory = '    directory = "Performance",\n' if performance_parent(name) else ""
    lists = "".join(
        f"    {rule} = [\n" + "".join(f'        "{path}",\n' for r, path in entries if r == rule) + "    ],\n"
        for rule in ("process", "copy") if any(r == rule for r, _ in entries)
    )
    return (
        'load("//tools:resources.bzl", "module_resources", "module_resources_data")\n',
        '    # `Bundle.module`, as SwiftPM generates it, for the resources below.\n'
        f'    srcs = glob(["**/*.swift"]) + [":{target}Accessor"],\n',
        f'    data = module_resources_data("{target}"),\n',
        f"\n# The {what} (RESOURCES in scripts/modules.py), in the bundle SwiftPM builds for them.\n"
        "module_resources(\n"
        f'    name = "{target}",\n'
        f'    bundle_name = "{PROJECT}_{name}",\n'
        f'    bundle_id = "{PROJECT.lower()}.{name}.resources",\n'
        f"{directory}"
        f"{lists}"
        ")\n",
    )


def exclude_arg(path):
    files = excluded(path)
    if files == ["BUILD.bazel"]:
        return ", exclude: bazelFiles"
    if files:
        return ", exclude: [" + ", ".join(f'"{f}"' for f in files) + "]"
    return ""


def package_swift():
    lines = [
        f"// swift-tools-version: {SWIFT}",
    ] + (["import CompilerPluginSupport"] if MACROS else []) + [
        "import PackageDescription",
        "",
        "// GENERATED by scripts/modules.py — edit the table there, then run `just modules`.",
        "//",
        "// The published package definition. Bazel is the development build system; both are generated",
        "// from the same table, and `just verify` builds and tests with both.",
        "",
        "// Every target directory holds a BUILD.bazel, which SwiftPM must be told to ignore.",
        'let bazelFiles = ["BUILD.bazel"]',
        "",
    ]
    if APPLE_ONLY_PACKAGES:
        lines += [
            "// Where the Apple-only packages' products are linked (APPLE_ONLY_PACKAGES in scripts/modules.py).",
            "let applePlatforms: [Platform] = [" + ", ".join(f".{p}" for p in APPLE_PLATFORMS) + "]",
            "",
        ]
    conditional_modules = sorted({d for deps in PLATFORM_CONDITIONAL_DEPENDENCIES.values() for d in deps}
                                 | {module for module, _ in closure_conditions()})
    if conditional_modules:
        lines.append("// The platforms that build each module linked under a condition (PLATFORM_CONDITIONAL_DEPENDENCIES in scripts/modules.py).")
        lines += [f"let {platforms_variable(d)}: [Platform] = [" + ", ".join(f".{p}" for p in module_platforms(d)) + "]" for d in conditional_modules]
        lines.append("")
    lines += [
        "// Typed arrays of their own: as one `Package(...)` expression, a large manifest is too big for",
        "// the type checker.",
        "let products: [Product] = [",
    ]
    if umbrella():
        lines.append(f'    .library(name: "{PROJECT}", targets: ["{PROJECT}"]),')
    lines += [f'    .library(name: "{m[0]}", targets: ["{m[0]}"]),' for m in library_modules()]
    lines += [f'    .executable(name: "{e[0]}", targets: ["{e[0]}"]),' for e in EXECUTABLES]
    lines += [f'    .library(name: "{d[0]}", type: .dynamic, targets: ["{d[0]}"]),' for d in DYNAMIC_LIBRARIES]
    lines += [f'    .plugin(name: "{p[0]}", targets: ["{p[0]}"]),' for p in PLUGINS]
    lines += ["]", "", "let dependencies: [Package.Dependency] = ["]
    lines += [f'    .package(url: "{url}", {requirement(version)}),' for _, url, version in package_dependencies()]
    lines += ["]", "", "let targets: [Target] = ["]
    group = None
    for name, g, _, deps in package_modules():
        if g != group:
            lines.append(f"    // {g}")
            group = g
        ex = exclude_arg(f"Sources/{name}")
        settings = ', swiftSettings: [.define("MOCKING", .when(configuration: .debug))]' if MOCKING in deps else ""
        resources = resources_arg(name)
        if deps:
            dl = ", ".join(spm_dep(d, name) for d in deps)
            lines.append(f'    .target(name: "{name}", dependencies: [{dl}]{ex}{resources}{settings}),')
        else:
            lines.append(f'    .target(name: "{name}"{ex}{resources}),')
    for name, g, _, deps in MACROS:
        lines.append(f"    // {g}: compiler plugin")
        dl = ", ".join(spm_dep(d) for d in deps)
        lines.append(f'    .macro(name: "{name}", dependencies: [{dl}]{exclude_arg(f"Sources/{name}")}),')
    if EXECUTABLES:
        lines += ["", "    // Executables"]
    for name, _, deps in EXECUTABLES:
        dl = ", ".join(spm_dep(d) for d in deps)
        lines.append(f'    .executableTarget(name: "{name}", dependencies: [{dl}]{exclude_arg(f"Sources/{name}")}),')
    if DYNAMIC_LIBRARIES:
        lines += ["", "    // Dynamic libraries: C, each a `.dynamic` product of its own (DYNAMIC_LIBRARIES in scripts/modules.py)."]
    for name, _ in DYNAMIC_LIBRARIES:
        lines.append(f'    .target(name: "{name}"{exclude_arg(f"Sources/{name}")}),')
    if PLUGINS:
        lines += ["", "    // Command plugins (PLUGINS in scripts/modules.py), which Bazel doesn't build"]
    for name, verb, description, reason in PLUGINS:
        intent = f".custom(verb: {swift_string(verb)}, description: {swift_string(description)})"
        permissions = "" if reason is None else f", permissions: [.writeToPackageDirectory(reason: {swift_string(reason)})]"
        lines.append(f'    .plugin(name: "{name}", capability: .command(intent: {intent}{permissions}){exclude_arg(f"Plugins/{name}")}),')
    all_deps = ", ".join(f'"{m[0]}"' for m in umbrella_modules())
    support_deps = ", ".join(spm_dep(d) for d in TEST_SUPPORT_DEPENDENCIES)
    support_deps_arg = f"dependencies: [{support_deps}], " if TEST_SUPPORT_DEPENDENCIES else ""
    if umbrella():
        lines += [
            "",
            f"    // Umbrella: `import {PROJECT}` imports every module.",
            f'    .target(name: "{PROJECT}", dependencies: [{all_deps}], exclude: bazelFiles),',
        ]
    lines += [
        "",
        "    // Shared fixtures (data only) for every test target.",
        f'    .target(name: "{TEST_SUPPORT}", {support_deps_arg}path: "Tests/{TEST_SUPPORT}", exclude: bazelFiles),',
        "",
    ]
    if TEST_HELPERS:
        lines += ["    // Shared checks the test targets run (TEST_HELPERS in scripts/modules.py); no product names them."]
        for name, _, deps in TEST_HELPERS:
            dl = ", ".join(spm_dep(d) for d in deps)
            lines.append(f'    .target(name: "{name}", dependencies: [{dl}], path: "Tests/{name}", exclude: bazelFiles),')
        lines.append("")
    for name, deps in package_tests():
        dl = ", ".join(spm_dep(d, name) for d in deps)
        files = excluded(f"Tests/{name}")
        ex = "[" + ", ".join(f'"{f}"' for f in files) + "]" if files != ["BUILD.bazel"] else "bazelFiles"
        lines.append(f'    .testTarget(name: "{name}", dependencies: [{dl}], exclude: {ex}{resources_arg(name)}),')
    if PERFORMANCE_TESTS:
        lines += [
            "",
            "    // Speed-reliant tests, split from the target of the same module (PERFORMANCE_TESTS in scripts/modules.py).",
        ]
        for name, deps in TEST_TARGETS:
            if name in PERFORMANCE_TESTS:
                dl = ", ".join(spm_dep(d) for d in performance_dependencies(deps))
                lines.append(f'    .testTarget(name: "{performance_target(name)}", dependencies: [{dl}], path: "Tests/{name}/Performance"{resources_arg(performance_target(name))}),')
    lines += [
        "]",
        "",
        "let package = Package(",
        f'    name: "{PROJECT}",',
        "    // Keep in step with .bazelrc's --macos_minimum_os.",
        f"    platforms: {PLATFORMS},",
        "    products: products,",
        "    dependencies: dependencies,",
        "    targets: targets",
        ")",
        "",
    ]
    return "\n".join(lines)


def dependency_manifest():
    deps = "".join(f'        .package(url: "{url}", {requirement(version)}),\n' for _, url, version in PACKAGES)
    return (
        "// swift-tools-version: 6.0\n"
        "import PackageDescription\n\n"
        "// GENERATED by scripts/modules.py. Dependency-resolution manifest for Bazel\n"
        "// (rules_swift_package_manager); it lists the same packages as the root Package.swift.\n"
        "// After changing it, run `just resolve`.\n"
        "let package = Package(\n"
        f'    name: "{PROJECT}Dependencies",\n'
        f'    platforms: [.macOS("{MACOS_MINIMUM}")],\n'
        f"    dependencies: [\n{deps}    ]\n"
        ")\n"
    )


def build_bazel(name, description, deps, linked=()):
    """A module's BUILD.bazel. `linked` names modules its catalog links to without importing them:
    their archives join its docs' dependencies alone."""
    resources_load, srcs_attr, data_attr, resources = resources_bazel(name)
    deps_attr = bazel_deps(deps, target=name)
    defines_attr = (
        "    # Mock<Protocol> types from @Mockable, in debug builds only (MOCKING in scripts/modules.py).\n"
        '    defines = select({"//tools:debug": ["MOCKING"], "//conditions:default": []}),\n'
    ) if MOCKING in deps else ""
    testing_attr = (
        "    # Imports Testing, found on the developer search paths (TESTING_MODULES in scripts/modules.py).\n"
        "    always_include_developer_search_paths = True,\n"
    ) if name in TESTING_MODULES else ""
    if name in IOS_MODULES:
        return (
            "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
            f"{resources_load}"
            'load("//tools:swift_rules.bzl", "swift_library")\n\n'
            f"# {description}\n"
            "# iOS only (IOS_MODULES in scripts/modules.py): built for the simulator through the app and the\n"
            "# simulator tests, skipped by `bazel build //...` on the Mac.\n"
            "swift_library(\n"
            f'    name = "{name}",\n'
            f"{srcs_attr}"
            f"{data_attr}"
            f'    module_name = "{name}",\n'
            f"{defines_attr}"
            f"{deps_attr}"
            '    target_compatible_with = ["@platforms//os:ios"],\n'
            '    visibility = ["//visibility:public"],\n'
            ")\n"
            f"{resources}"
        )
    if name in EXAMPLE_MODULES:
        return (
            "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
            f"{resources_load}"
            'load("//tools:swift_rules.bzl", "swift_library")\n\n'
            f"# {description}\n"
            "# An example (EXAMPLE_MODULES in scripts/modules.py): no product, umbrella import or docs.\n"
            "swift_library(\n"
            f'    name = "{name}",\n'
            f"{srcs_attr}"
            f"{data_attr}"
            f'    module_name = "{name}",\n'
            f"{defines_attr}"
            f"{deps_attr}"
            f"{testing_attr}"
            '    visibility = ["//visibility:public"],\n'
            ")\n"
            f"{resources}"
        )
    doc_deps = "".join(f'        "{bazel_label(d)}:{d}Documentation",\n' for d in [*deps, *linked] if "/" not in d and not is_macro(d))
    doc_deps_attr = f"    deps = [\n{doc_deps}    ],\n" if doc_deps else ""
    docs_testing_attr = "    always_include_developer_search_paths = True,\n" if name in TESTING_MODULES else ""
    platforms = [(p, minimum) for p, (minimum, modules) in EXTRA_PLATFORMS.items() if name in modules]
    # Sorted by file, as buildifier orders loads.
    platform_loads = "".join(
        f'load("@rules_apple//apple:{p.lower()}.bzl", "{p.lower()}_build_test")\n' for p, _ in sorted(platforms, key=lambda p: p[0].lower())
    )
    platform_build_tests = "".join(
        f"\n# Builds the library for the {p} simulator, so `bazel build //...` checks it compiles\n"
        "# there (EXTRA_PLATFORMS in scripts/modules.py).\n"
        f"{p.lower()}_build_test(\n"
        f'    name = "{name}_{p}",\n'
        f'    minimum_os_version = "{minimum}",\n'
        f'    targets = [":{name}"],\n'
        ")\n"
        for p, minimum in platforms
    )
    if name in CATALYST_MODULES:
        platform_build_tests += (
            "\n# Compiles the library for Mac Catalyst, so `bazel build //...` checks it compiles\n"
            "# there (CATALYST_MODULES in scripts/modules.py).\n"
            "catalyst_build_test(\n"
            f'    name = "{name}_catalyst",\n'
            f'    minimum_os_version = "{IOS_MINIMUM}",\n'
            f'    targets = [":{name}"],\n'
            ")\n"
        )
    catalyst_load = 'load("//tools:catalyst.bzl", "catalyst_build_test")\n' if name in CATALYST_MODULES else ""
    shaders = (
        "\n# The module's Metal sources and the Swift files tools/metallibs.py compiles them into, which\n"
        "# //tools:metallibs_test checks agree.\n"
        "filegroup(\n"
        '    name = "shaders",\n'
        '    srcs = glob(["Shaders/*.metal", "*Shader+*Library.swift"]),\n'
        '    visibility = ["//tools:__pkg__"],\n'
        ")\n"
    ) if os.path.isdir(os.path.join(ROOT, "Sources", name, "Shaders")) else ""
    require_documentation_attr = "    require_documentation = True,\n" if name in DOCUMENTED_MODULES else ""
    return (
        "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
        f"{platform_loads}"
        f"{catalyst_load}"
        'load("//tools:docc.bzl", "docc_archive")\n'
        f"{resources_load}"
        'load("//tools:swift_rules.bzl", "swift_library")\n\n'
        f"# {description}\n"
        "swift_library(\n"
        f'    name = "{name}",\n'
        f"{srcs_attr}"
        f"{data_attr}"
        f'    module_name = "{name}",\n'
        f"{defines_attr}"
        f"{deps_attr}"
        f"{testing_attr}"
        '    visibility = ["//visibility:public"],\n'
        ")\n"
        f"{resources}"
        "\n"
        "# The module's DocC archive, merged into //:docs. `manual` keeps it out of `bazel build //...`.\n"
        "docc_archive(\n"
        f'    name = "{name}Documentation",\n'
        f'    module = ":{name}",\n'
        '    catalog = glob(["*.docc/**"], allow_empty = True),\n'
        f"{doc_deps_attr}"
        f"{require_documentation_attr}"
        f"{docs_testing_attr}"
        '    tags = ["manual"],\n'
        '    visibility = ["//visibility:public"],\n'
        ")\n"
        f"{shaders}"
        f"{platform_build_tests}"
    )


def executable_build_bazel(name, description, deps):
    deps_attr = bazel_deps(deps)
    return (
        "# GENERATED by scripts/modules.py — edit EXECUTABLES there, then run `just modules`.\n\n"
        'load("//tools:swift_rules.bzl", "swift_binary")\n\n'
        f"# {description}\n"
        "swift_binary(\n"
        f'    name = "{name}",\n'
        '    srcs = glob(["**/*.swift"]),\n'
        f'    module_name = "{name}",\n'
        f"{deps_attr}"
        '    visibility = ["//visibility:public"],\n'
        ")\n"
    )


def dynamic_library_build_bazel(name, description):
    return (
        "# GENERATED by scripts/modules.py — edit DYNAMIC_LIBRARIES there, then run `just modules`.\n\n"
        'load("@rules_cc//cc:cc_binary.bzl", "cc_binary")\n'
        'load("@rules_cc//cc:cc_import.bzl", "cc_import")\n'
        'load("@rules_cc//cc:cc_library.bzl", "cc_library")\n\n'
        f"# {description}\n"
        "# A dynamic library (DYNAMIC_LIBRARIES in scripts/modules.py): its C sources, compiled with DEBUG\n"
        "# in debug builds only.\n"
        "cc_library(\n"
        f'    name = "{name}Sources",\n'
        '    srcs = glob(["*.c"]),\n'
        '    hdrs = glob(["include/*.h"]),\n'
        '    includes = ["include"],\n'
        '    local_defines = select({"//tools:debug": ["DEBUG=1"], "//conditions:default": []}),\n'
        "    # Nothing references the library's symbols by name, so the linker would otherwise drop them.\n"
        "    alwayslink = True,\n"
        "    # Visible so an app can wrap them in a framework of its own (Example/BUILD.bazel does for iOS).\n"
        '    visibility = ["//visibility:public"],\n'
        ")\n\n"
        "# The dylib itself, found at launch through the @rpath of whatever links it.\n"
        "cc_binary(\n"
        f'    name = "lib{name}.dylib",\n'
        "    linkshared = True,\n"
        f'    linkopts = ["-Wl,-install_name,@rpath/lib{name}.dylib"],\n'
        f'    deps = [":{name}Sources"],\n'
        ")\n\n"
        "# What a test or a macOS app depends on to link the dylib at launch; macos_application copies it\n"
        "# into Contents/Frameworks.\n"
        "cc_import(\n"
        f'    name = "{name}",\n'
        '    hdrs = glob(["include/*.h"]),\n'
        f'    shared_library = ":lib{name}.dylib",\n'
        '    visibility = ["//visibility:public"],\n'
        ")\n"
    )


def macro_build_bazel(name, description, deps):
    return (
        "# GENERATED by scripts/modules.py — edit MACROS there, then run `just modules`.\n\n"
        'load("//tools:swift_rules.bzl", "swift_compiler_plugin")\n\n'
        f"# {description}\n"
        "swift_compiler_plugin(\n"
        f'    name = "{name}",\n'
        '    srcs = [":srcs"],\n'
        f'    module_name = "{name}",\n'
        f"{bazel_deps(deps)}"
        '    visibility = ["//visibility:public"],\n'
        ")\n\n"
        "# The sources, which the plugin's tests also compile as a library (MACROS in scripts/modules.py).\n"
        "filegroup(\n"
        '    name = "srcs",\n'
        '    srcs = glob(["**/*.swift"]),\n'
        '    visibility = ["//Tests:__subpackages__"],\n'
        ")\n"
    )


def macro_library_bazel(name):
    """The testonly library of plugin `name`'s sources that a test package links (see MACROS)."""
    deps = dict((m[0], m[3]) for m in MACROS)[name]
    return (
        f"# {name}'s sources as a library of the same module, for these tests to link (MACROS in\n"
        "# scripts/modules.py). Its `@main` entry point is renamed, as swift_compiler_plugin renames\n"
        "# the plugin's, so it doesn't clash with the test runner's.\n"
        "swift_library(\n"
        f'    name = "{name}Library",\n'
        "    testonly = True,\n"
        f'    srcs = ["//Sources/{name}:srcs"],\n'
        f'    module_name = "{name}",\n'
        "    copts = [\n"
        '        "-Xfrontend",\n'
        '        "-entry-point-function-name",\n'
        '        "-Xfrontend",\n'
        f'        "{name}_main",\n'
        "    ],\n"
        f'    tags = ["{RELEASE_EXCLUDED_TAG}"],\n'
        f"{bazel_deps(deps)}"
        ")\n\n"
    )


def macros_bzl():
    packages = "".join(f'    "Sources/{name}",\n' for name in macro_names())
    return (
        '"""GENERATED by scripts/modules.py (MACROS) — edit the table there, then run `just modules`."""\n\n'
        "# The source packages that hold a compiler plugin rather than a library: the root BUILD.bazel\n"
        "# leaves them out of the docs and the products.\n"
        f"MACRO_PACKAGES = [\n{packages}]\n"
    )


def test_support_build_bazel():
    deps_attr = bazel_deps(TEST_SUPPORT_DEPENDENCIES)
    return (
        "# GENERATED by scripts/modules.py — edit TEST_SUPPORT_DEPENDENCIES there, then run `just modules`.\n\n"
        'load("//tools:swift_rules.bzl", "swift_library")\n\n'
        "# Shared fixtures for every test target: data and generators only, no assertion helpers.\n"
        "swift_library(\n"
        f'    name = "{TEST_SUPPORT}",\n'
        "    testonly = True,\n"
        '    srcs = glob(["**/*.swift"]),\n'
        f'    module_name = "{TEST_SUPPORT}",\n'
        f"{deps_attr}"
        '    visibility = ["//visibility:public"],\n'
        ")\n"
    )


def test_helper_build_bazel(name, description, deps):
    return (
        "# GENERATED by scripts/modules.py — edit TEST_HELPERS there, then run `just modules`.\n\n"
        'load("//tools:swift_rules.bzl", "swift_library")\n\n'
        f"# {description}\n"
        "# Test-only (TEST_HELPERS in scripts/modules.py): visible to the test packages, and to the root\n"
        "# package's //:package_swift_test, so no library under Sources/ can depend on it.\n"
        "swift_library(\n"
        f'    name = "{name}",\n'
        "    testonly = True,\n"
        '    srcs = glob(["**/*.swift"]),\n'
        f'    module_name = "{name}",\n'
        f"{bazel_deps(deps)}"
        '    visibility = [\n'
        '        "//:__pkg__",\n'
        '        "//Tests:__subpackages__",\n'
        "    ],\n"
        ")\n"
    )


def test_helpers_bzl():
    packages = "".join(f'    "Tests/{name}",\n' for name in test_helpers())
    return (
        '"""GENERATED by scripts/modules.py (TEST_HELPERS) — edit the table there, then run `just modules`."""\n\n'
        "# The packages under Tests/ that hold a test helper, a library rather than tests: the root\n"
        "# BUILD.bazel leaves them out of the test bundles and checks them against Package.swift.\n"
        f"TEST_HELPER_PACKAGES = [\n{packages}]\n"
    )


def env_inherit_attr(name):
    """The `env_inherit` line for test target `name`'s runners (TEST_ENVIRONMENT), or nothing."""
    variables = TEST_ENVIRONMENT.get(name)
    if not variables:
        return ""
    return "    env_inherit = [" + ", ".join(f'"{v}"' for v in variables) + "],\n"


def test_targets_bazel(name, deps, size, srcs, tags, test_tags=(), simulator=False, environment=None):
    """One test module: its library, the swift_test that `bazel test` runs, and the Xcode bundle; with
    `simulator`, the ios_unit_test that runs the same library in the simulator too (SIMULATOR_TESTS).

    `tags` go on the library and every runner; `test_tags` go on the swift_test alone. `environment`
    names the TEST_ENVIRONMENT entry its runners inherit, `name` by default."""
    env_attr = env_inherit_attr(environment or name)
    tags_attr = f"    tags = {tags},\n".replace("'", '"') if tags else ""
    test_tags_attr = (f"    tags = {list(tags) + list(test_tags)},\n".replace("'", '"')
                      if tags or test_tags else "")
    # SnapshotTesting finds a reference beside the test file through #filePath, which Bazel makes
    # relative to the workspace, and a test runs from its runfiles: so the references go in them.
    # A test target's fixtures (RESOURCES) are a bundle of their own, found by `Bundle.module`.
    resources = bool(RESOURCES.get(name))
    srcs += f' + [":{resources_target(name)}Accessor"]' if resources else ""
    data = (['glob(["__Snapshots__/**"], allow_empty = True)'] if "swift-snapshot-testing/SnapshotTesting" in deps else []) \
        + ([f'module_resources_data("{resources_target(name)}")'] if resources else [])
    data_attr = f"    data = {' + '.join(data)},\n" if data else ""
    compatible_attr = ('    target_compatible_with = select({\n'
                       '        # APPLE_ONLY_TESTS in scripts/modules.py: nothing to run elsewhere.\n'
                       '        "@platforms//os:macos": [],\n'
                       '        "//conditions:default": ["@platforms//:incompatible"],\n'
                       '    }),\n'
                       if name in APPLE_ONLY_TESTS else "")
    return (
        "swift_library(\n"
        f'    name = "{name}Library",\n'
        "    testonly = True,\n"
        "    # Tests are found through metadata the linker would otherwise drop, since nothing\n"
        "    # references them by name.\n"
        "    alwayslink = True,\n"
        f"    srcs = {srcs},\n"
        f"{data_attr}"
        f'    module_name = "{name}",\n'
        f"{tags_attr}"
        "    # Read by //:package_swift_test, which checks Package.swift against the Bazel graph.\n"
        '    visibility = ["//:__pkg__"],\n'
        f"{bazel_deps(deps, [platform for platform, _ in tested_platforms(name)] + (['macCatalyst'] if name in CATALYST_TESTS else []), target=name, testing=True)}"
        ")\n\n"
        "# `bazel test` / `just test`: a standalone executable, fast to start and run in Bazel's sandbox.\n"
        "swift_test(\n"
        f'    name = "{name}",\n'
        f"{env_attr}"
        f'    size = "{size}",\n'
        f"{test_tags_attr}"
        f"{compatible_attr}"
        f'    deps = [":{name}Library"],\n'
        ")\n\n"
        "# The generated Xcode project: a real .xctest bundle (an MH_BUNDLE), which is what Xcode's test\n"
        "# runner loads. `manual` keeps it out of `bazel test //...`; it runs through xcodebuild, so it\n"
        "# is only for Xcode. XCTest refuses exit tests in a sandboxed host, hence `no-sandbox`.\n"
        "macos_unit_test(\n"
        f'    name = "{name}Bundle",\n'
        f'    bundle_name = "{name}",\n'
        f'    size = "{size}",\n'
        f'    minimum_os_version = "{MACOS_MINIMUM}",\n'
        '    tags = ["manual", "no-sandbox"],\n'
        "    # Visible so `//:xcodeproj` can name it as a top-level target.\n"
        '    visibility = ["//visibility:public"],\n'
        f'    deps = [":{name}Library"],\n'
        ")\n"
        + "".join(platform_test_bazel(name, platform, minimum, tags) for platform, minimum in tested_platforms(name))
        + (catalyst_test_bazel(name, size, tags) if name in CATALYST_TESTS else "")
    ) + (simulator_half_bazel(name, deps, srcs, tags, env_attr) if simulator else "")


def tested_platforms(name):
    """The (platform, minimum) pairs of TESTED_PLATFORMS that run test target `name`."""
    return [(platform, IOS_MINIMUM if platform == "iOS" else EXTRA_PLATFORMS[platform][0])
            for platform, targets in TESTED_PLATFORMS.items() if name in targets]


def platform_test_bazel(name, platform, minimum, tags):
    """The unit test that runs test target `name`'s library in `platform`'s simulator."""
    # One simulator at a time (SIMULATOR_TEST_TAG).
    tags_attr = f"    tags = {list(tags) + [SIMULATOR_TEST_TAG]},\n".replace("'", '"')
    # The test host gives an iOS run an application identifier, and with it a keychain, and a
    # connected window scene.
    host = ("# Hosted by //tools/test_host, whose entitlements give the tests a keychain and whose\n"
            "# window scene lets them present view controllers.\n",
            '    test_host = "//tools/test_host",\n') if platform == "iOS" else ("", "")
    return (
        f"\n# `bazel test` / `just test` on {platform}: the bundle, run in a new {platform} simulator by\n"
        f"# //tools:{platform.lower()}_test_runner (TESTED_PLATFORMS in scripts/modules.py). Booting one takes\n"
        f"# much of a minute on its own; `{SIMULATOR_TEST_TAG}` runs one simulator test at a time.\n"
        f"{host[0]}"
        f"{platform.lower()}_unit_test(\n"
        f'    name = "{name}_{platform}",\n'
        '    size = "medium",\n'
        f'    minimum_os_version = "{minimum}",\n'
        f'    runner = "//tools:{platform.lower()}_test_runner",\n'
        f"{tags_attr}"
        f"{host[1]}"
        f'    deps = [":{name}Library"],\n'
        ")\n"
    )


def catalyst_test_bazel(name, size, tags):
    """The catalyst_test that builds test target `name`'s swift_test for Mac Catalyst and runs it."""
    tags_attr = f"    tags = {list(tags)},\n".replace("'", '"') if tags else ""
    return (
        "\n# `bazel test` / `just test` for Mac Catalyst: the swift_test above, built with the Catalyst\n"
        "# target triple by //tools:catalyst.bzl and run on the Mac (CATALYST_TESTS in scripts/modules.py).\n"
        "catalyst_test(\n"
        f'    name = "{name}_macCatalyst",\n'
        f'    size = "{size}",\n'
        f'    minimum_os_version = "{IOS_MINIMUM}",\n'
        f"{tags_attr}"
        f'    test = ":{name}",\n'
        ")\n"
    )


def simulator_half_bazel(name, deps, srcs, tags, env_attr):
    """The same tests as test target `name`'s library, built for iOS and run in the simulator as well
    (SIMULATOR_TESTS): a library of their own, without the Mac's snapshot references, which
    rules_apple would flatten into the bundle as resources, but with its fixtures' bundle (RESOURCES),
    which it nests; and the ios_unit_test."""
    tags_attr = f"    tags = {tags},\n".replace("'", '"') if tags else ""
    data_attr = '    data = module_resources_data("Resources"),\n' if RESOURCES.get(name) else ""
    return (
        "\n# The same tests in the iOS simulator (SIMULATOR_TESTS in scripts/modules.py), where the code\n"
        "# under `#if canImport(UIKit)` compiles. iOS only, so `bazel build //...` builds it through the\n"
        "# bundle below alone.\n"
        "swift_library(\n"
        f'    name = "{name}SimulatorLibrary",\n'
        "    testonly = True,\n"
        "    alwayslink = True,\n"
        f"    srcs = {srcs},\n"
        f"{data_attr}"
        f'    module_name = "{name}",\n'
        f"{tags_attr}"
        '    target_compatible_with = ["@platforms//os:ios"],\n'
        f"{bazel_deps(deps, testing=True, ios=True)}"
        ")\n\n"
        "# Run inside the test host (tools/test_host), which gives windows a scene.\n"
        f"# `{SIMULATOR_TEST_TAG}` runs one simulator test at a time (.bazelrc).\n"
        "ios_unit_test(\n"
        f'    name = "{name}Simulator",\n'
        # rules_apple's runner hands the simulator only the variables listed here.
        f"{env_attr}"
        f'    size = "{TEST_SIZES.get(name, "medium")}",\n'
        f'    minimum_os_version = "{IOS_MINIMUM}",\n'
        "    tags = [\n" + "".join(f'        "{t}",\n' for t in tags + [SIMULATOR_TEST_TAG]) + "    ],\n"
        "    # The simulator is the Mac's alone, so elsewhere `bazel test //...` skips the bundle.\n"
        "    target_compatible_with = select({\n"
        '        "@platforms//os:macos": [],\n'
        '        "//conditions:default": ["@platforms//:incompatible"],\n'
        "    }),\n"
        '    test_host = "//tools/test_host",\n'
        '    visibility = ["//visibility:public"],\n'
        f'    deps = [":{name}SimulatorLibrary"],\n'
        ")\n"
    )


def simulator_test_build_bazel(name, deps, size):
    """A test module run in the iOS simulator: its library, its snapshot references, its fixtures
    (RESOURCES) and the ios_unit_test."""
    resources_load, srcs_attr, _, resources = resources_bazel(name)
    data_attr = ('    data = [":Snapshots"] + module_resources_data("Resources"),\n' if resources
                 else '    data = [":Snapshots"],\n')
    return (
        "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
        'load("@rules_apple//apple:ios.bzl", "ios_unit_test")\n'
        'load("@rules_apple//apple:resources.bzl", "apple_resource_bundle")\n'
        f"{resources_load}"
        'load("//tools:swift_rules.bzl", "swift_library")\n\n'
        "# The tests, run in the iOS simulator: the target depends on an iOS module (IOS_MODULES in\n"
        f"# scripts/modules.py). Tagged `{RELEASE_EXCLUDED_TAG}`, like every target but the speed-reliant ones, and\n"
        f"# its test `{SIMULATOR_TEST_TAG}`, so one simulator test runs at a time.\n"
        "swift_library(\n"
        f'    name = "{name}Library",\n'
        "    testonly = True,\n"
        f"{srcs_attr}"
        f"{data_attr}"
        f'    module_name = "{name}",\n'
        f'    tags = ["{RELEASE_EXCLUDED_TAG}"],\n'
        '    target_compatible_with = ["@platforms//os:ios"],\n'
        f"{bazel_deps(deps)}"
        ")\n\n"
        "# The snapshot references under __Snapshots__, which the tests read from their bundle\n"
        "# (tools/snapshots; `just record-snapshots` rewrites them).\n"
        "apple_resource_bundle(\n"
        '    name = "Snapshots",\n'
        "    testonly = True,\n"
        '    structured_resources = glob(["__Snapshots__/**"], allow_empty = True),\n'
        f'    tags = ["{RELEASE_EXCLUDED_TAG}"],\n'
        ")\n\n"
        "# `bazel test` and the generated Xcode project both run this bundle in the simulator, inside the\n"
        "# test host (tools/test_host), which gives windows a scene.\n"
        f"# `{SIMULATOR_TEST_TAG}` runs one simulator test at a time (.bazelrc).\n"
        "ios_unit_test(\n"
        f'    name = "{name}",\n'
        f"{env_inherit_attr(name)}"
        f'    size = "{size}",\n'
        f'    minimum_os_version = "{IOS_MINIMUM}",\n'
        f'    tags = [\n        "{RELEASE_EXCLUDED_TAG}",\n        "{SIMULATOR_TEST_TAG}",\n    ],\n'
        "    # The simulator is the Mac's alone, so elsewhere `bazel test //...` skips the bundle.\n"
        "    target_compatible_with = select({\n"
        '        "@platforms//os:macos": [],\n'
        '        "//conditions:default": ["@platforms//:incompatible"],\n'
        "    }),\n"
        '    test_host = "//tools/test_host",\n'
        '    visibility = ["//visibility:public"],\n'
        f'    deps = [":{name}Library"],\n'
        ")\n"
        f"{resources}"
    )


def test_build_bazel(name, deps):
    size = TEST_SIZES.get(name, "small")
    if simulator_only(name):
        # Booting a simulator takes much of a minute on its own.
        return simulator_test_build_bazel(name, deps, TEST_SIZES.get(name, "medium"))
    simulator = name in SIMULATOR_TESTS
    resources_load, _, _, resources = resources_bazel(name)
    performance_load, _, _, performance_resources = resources_bazel(performance_target(name)) if name in PERFORMANCE_TESTS else ("", "", "", "")
    resources_load = resources_load or performance_load
    # Sorted by file, as buildifier orders loads.
    unit_test_loads = "".join(
        f'load("@rules_apple//apple:{platform}.bzl", "{platform}_unit_test")\n'
        for platform in sorted({"macos", *(platform.lower() for platform, _ in tested_platforms(name)), *(["ios"] if simulator else [])})
    )
    catalyst_load = 'load("//tools:catalyst.bzl", "catalyst_test")\n' if name in CATALYST_TESTS else ""
    header = (
        "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
        f"{unit_test_loads}"
        f"{catalyst_load}"
        f"{resources_load}"
        'load("//tools:swift_rules.bzl", "swift_library", "swift_test")\n\n'
    )
    excluded_note = (
        f"Tagged `{RELEASE_EXCLUDED_TAG}`: none of these relies on speed, so\n"
        "# `--config=release` neither builds nor runs them (.bazelrc).\n"
    )
    header += "".join(macro_library_bazel(d) for d in deps if is_macro(d))
    if name not in PERFORMANCE_TESTS:
        return (header + "# The tests, built once and linked into two runners.\n# " + excluded_note
                + test_targets_bazel(name, deps, size, 'glob(["**/*.swift"])', [RELEASE_EXCLUDED_TAG], simulator=simulator)
                + resources)
    return (
        header
        + "# The tests, built once and linked into two runners; the speed-reliant ones, in Performance/, are\n"
        + f"# {performance_target(name)} below. " + excluded_note
        + test_targets_bazel(name, deps, size, 'glob(["**/*.swift"], exclude = ["Performance/**"])', [RELEASE_EXCLUDED_TAG], simulator=simulator)
        + "\n# The speed-reliant tests (PERFORMANCE_TESTS in scripts/modules.py): debug and `--config=release`\n"
        + f"# both run them, each alone after every other action (`{PERFORMANCE_TEST_TAG}`).\n"
        + test_targets_bazel(performance_target(name), performance_dependencies(deps), PERFORMANCE_TEST_SIZE, 'glob(["Performance/**/*.swift"])', [],
                             [PERFORMANCE_TEST_TAG], environment=name)
        + resources
        + performance_resources
    )


def performance_tests_bzl():
    packages = "".join(f'    "Tests/{name}",\n' for name in PERFORMANCE_TESTS)
    return (
        '"""GENERATED by scripts/modules.py (PERFORMANCE_TESTS) — edit the list there, then run `just modules`."""\n\n'
        "# The test packages that also hold a speed-reliant target, `<Name>PerformanceTests` built from\n"
        "# Performance/, which the root BUILD.bazel cannot find from the directory layout alone.\n"
        f"PERFORMANCE_TEST_PACKAGES = [\n{packages}]\n"
    )


def executables_bzl():
    packages = "".join(f'    "Sources/{e[0]}",\n' for e in EXECUTABLES)
    return (
        '"""GENERATED by scripts/modules.py (EXECUTABLES) — edit the table there, then run `just modules`."""\n\n'
        "# The source packages that hold a swift_binary rather than a library: the root BUILD.bazel\n"
        "# leaves them out of the docs and launches them from the Xcode project.\n"
        f"EXECUTABLE_PACKAGES = [\n{packages}]\n"
    )


def dynamic_libraries_bzl():
    packages = "".join(f'    "Sources/{d[0]}",\n' for d in DYNAMIC_LIBRARIES)
    return (
        '"""GENERATED by scripts/modules.py (DYNAMIC_LIBRARIES) — edit the table there, then run `just modules`."""\n\n'
        "# The source packages that hold a C dynamic library rather than a Swift module: the root\n"
        "# BUILD.bazel leaves them out of the docs.\n"
        f"DYNAMIC_LIBRARY_PACKAGES = [\n{packages}]\n"
    )


def benchmark_dep(d):
    """A benchmark target's dependency: a product of one of PACKAGES, or else a library module."""
    if "/" in d:
        package, product = d.split("/")
        return f'.product(name: "{product}", package: "{package}")'
    return f'.product(name: "{d}", package: "{PROJECT}")'


def benchmarks_package_swift():
    url, version = BENCHMARK_PACKAGE
    used = {d.split("/")[0] for _, deps in BENCHMARKS for d in deps if "/" in d}
    packages = "".join(f'        .package(url: "{u}", {requirement(v)}),\n' for identity, u, v in PACKAGES if identity in used)
    targets = "".join(
        "        .executableTarget(\n"
        f'            name: "{name}",\n'
        "            dependencies: [\n"
        '                .product(name: "Benchmark", package: "benchmark"),\n'
        + "".join(f"                {benchmark_dep(d)},\n" for d in deps)
        + "            ],\n"
        f'            path: "Benchmarks/{name}",\n'
        # packageAccess: false, or SwiftPM's own -package-name (this package's) comes later and wins.
        + ("            packageAccess: false,\n            swiftSettings: [.unsafeFlags([\"-package-name\", libraryPackageName])],\n"
           if name in PACKAGE_ACCESS_BENCHMARKS else "")
        + '            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]\n'
        "        ),\n"
        for name, deps in BENCHMARKS
    )
    package_name = (
        "// The package name SwiftPM compiles the library's modules with: its identity, the name of its\n"
        "// directory, lowercased, as a C identifier. A target compiled with it reaches the library's\n"
        "// `package` declarations (PACKAGE_ACCESS_BENCHMARKS); `packageAccess: false` leaves out\n"
        "// SwiftPM's own `-package-name`, this package's, which would otherwise come later and win.\n"
        "let libraryPackageName: String = {\n"
        "    let directory = URL(filePath: Context.packageDirectory).deletingLastPathComponent().lastPathComponent.lowercased()\n"
        "    let name = String(directory.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : \"_\" })\n"
        "    return name.first?.isNumber == true ? \"_\" + name : name\n"
        "}()\n\n"
    ) if PACKAGE_ACCESS_BENCHMARKS else ""
    return (
        f"// swift-tools-version: {SWIFT}\n"
        + ("import Foundation\n" if PACKAGE_ACCESS_BENCHMARKS else "")
        + "import PackageDescription\n\n"
        "// GENERATED by scripts/modules.py from BENCHMARKS: edit the table there, then run `just modules`.\n"
        "// Benchmarks live in their own package so the library and its tests never depend on the\n"
        "// benchmark framework. Run them with `just bench`; see Benchmarks/README.md.\n\n"
        + package_name
        + "let package = Package(\n"
        f'    name: "{PROJECT}Benchmarks",\n'
        f'    platforms: [.macOS("{MACOS_MINIMUM}")],\n'
        "    dependencies: [\n"
        "        // Named, so products name the package whatever its directory is called; its identity,\n"
        "        // and so its package name, is still the directory's name.\n"
        f'        .package(name: "{PROJECT}", path: ".."),\n'
        f'        .package(url: "{url}", from: "{version}"),\n'
        f"{packages}"
        "    ],\n"
        f"    targets: [\n{targets}    ]\n"
        ")\n"
    )


def test_scheme(name):
    """An Xcode scheme for the package that tests test target `name` alone. Xcode's own schemes
    either test nothing (a library's) or build every target (DebugDrawer-Package), so a platform
    that builds only some modules needs one per target. `.swiftpm/` is not committed: `just
    spm-platform-test` writes it there, where Xcode finds a package's shared schemes."""
    reference = (
        "            <BuildableReference\n"
        '               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{name}"\n'
        f'               BuildableName = "{name}"\n'
        f'               BlueprintName = "{name}"\n'
        '               ReferencedContainer = "container:">\n'
        "            </BuildableReference>\n"
    )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<!-- GENERATED by scripts/modules.py (TESTED_PLATFORMS) for `just spm-platform-test`. -->\n"
        '<Scheme LastUpgradeVersion = "1600" version = "1.7">\n'
        '   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">\n'
        "   </BuildAction>\n"
        '   <TestAction buildConfiguration = "Debug" shouldUseLaunchSchemeArgsEnv = "YES">\n'
        "      <Testables>\n"
        '         <TestableReference skipped = "NO">\n'
        f"{reference}"
        "         </TestableReference>\n"
        "      </Testables>\n"
        "   </TestAction>\n"
        "</Scheme>\n"
    )


def examples_bzl():
    packages = "".join(f'    "Sources/{name}",\n' for name in EXAMPLE_MODULES)
    return (
        '"""GENERATED by scripts/modules.py (EXAMPLE_MODULES) — edit the table there, then run `just modules`."""\n\n'
        "# The source packages of example modules, which have no DocC archive: the root BUILD.bazel\n"
        "# leaves them out of the docs.\n"
        f"EXAMPLE_PACKAGES = [\n{packages}]\n"
    )


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def main():
    duplicates = duplicate_definitions()
    if duplicates:
        sys.exit(f"scripts/modules.py defines {', '.join(duplicates)} more than once (a template update "
                 "can merge a second copy in); keep one, holding this project's rows, and delete the other")
    check()
    # Before the record is rewritten: it names the versions the sites hold now.
    replace_swift(ROOT, recorded_swift(ROOT) or (SWIFT, SWIFT_TOOLCHAIN), (SWIFT, SWIFT_TOOLCHAIN))
    write(os.path.join(ROOT, "tools", "swift_version.bzl"), swift_version_bzl())
    for name, _, description, deps in MODULES:
        d = os.path.join(ROOT, "Sources", name)
        write(os.path.join(d, "BUILD.bazel"), build_bazel(name, description, deps))
        # SwiftPM and Bazel both reject a module with no sources. Until a module has real
        # sources, it carries a file holding only its description.
        if not any(fn.endswith(".swift") for _, _, fns in os.walk(d) for fn in fns):
            write(os.path.join(d, f"{name}.swift"), f"// {name}: {description}\n")
    for name, deps in TEST_TARGETS:
        d = os.path.join(ROOT, "Tests", name)
        write(os.path.join(d, "BUILD.bazel"), test_build_bazel(name, deps))
        # SwiftPM rejects a target with no sources, and one left out of PERFORMANCE_TESTS would be
        # compiled into the module's own target, which release skips.
        performance = os.path.join(d, "Performance")
        has_performance = any(fn.endswith(".swift") for _, _, fns in os.walk(performance) for fn in fns)
        assert has_performance == (name in PERFORMANCE_TESTS), \
            f"{name}: Performance/ holds Swift sources exactly when the target is in PERFORMANCE_TESTS"
        clashes = snapshot_name_clashes(ROOT, name)
        assert not clashes, (
            f"{name}: snapshot references share a base name, which the Xcode project's flat test bundle can't hold; "
            "rename a test so each name is unique: " + "; ".join(" and ".join(paths) for paths in clashes)
        )
    for name, description, deps in EXECUTABLES:
        d = os.path.join(ROOT, "Sources", name)
        write(os.path.join(d, "BUILD.bazel"), executable_build_bazel(name, description, deps))
    for name, description in DYNAMIC_LIBRARIES:
        write(os.path.join(ROOT, "Sources", name, "BUILD.bazel"), dynamic_library_build_bazel(name, description))
    write(os.path.join(ROOT, "tools", "dynamic_libraries.bzl"), dynamic_libraries_bzl())
    for name, _, description, deps in MACROS:
        write(os.path.join(ROOT, "Sources", name, "BUILD.bazel"), macro_build_bazel(name, description, deps))
    write(os.path.join(ROOT, "Tests", TEST_SUPPORT, "BUILD.bazel"), test_support_build_bazel())
    for name, description, deps in TEST_HELPERS:
        write(os.path.join(ROOT, "Tests", name, "BUILD.bazel"), test_helper_build_bazel(name, description, deps))
    write(os.path.join(ROOT, "tools", "test_helpers.bzl"), test_helpers_bzl())
    write(os.path.join(ROOT, "tools", "executables.bzl"), executables_bzl())
    write(os.path.join(ROOT, "tools", "examples.bzl"), examples_bzl())
    write(os.path.join(ROOT, "tools", "macros.bzl"), macros_bzl())
    write(os.path.join(ROOT, "tools", "performance_tests.bzl"), performance_tests_bzl())
    names = [m[0] for m in umbrella_modules()]
    if umbrella():
        directory = os.path.join(ROOT, "Sources", PROJECT)
        write(os.path.join(directory, "BUILD.bazel"), build_bazel(PROJECT, f"Umbrella: `import {PROJECT}` imports every module.", names,
                                                             # The landing catalog may link a module left out of the umbrella.
                                                             linked=NON_UMBRELLA_MODULES))
        write(os.path.join(directory, f"{PROJECT}.swift"),
              f"// GENERATED by scripts/modules.py.\n//\n// Umbrella: `import {PROJECT}` imports every module.\n\n"
              + "".join(f"@_exported import {n}\n" for n in names))
    write(os.path.join(ROOT, "swift", "Package.swift"), dependency_manifest())
    write(os.path.join(ROOT, "Benchmarks", "Package.swift"), benchmarks_package_swift())
    # Written last: which files each target must exclude depends on the BUILD files above.
    write(os.path.join(ROOT, "Package.swift"), package_swift())


if __name__ == "__main__":
    # `just build-spm` asks which schemes to build for each platform in EXTRA_PLATFORMS:
    # `modules.py platform-modules tvOS`, and for Mac Catalyst: `modules.py catalyst-modules`.
    if sys.argv[1:2] == ["platform-modules"]:
        print("\n".join(EXTRA_PLATFORMS[sys.argv[2]][1]))
    elif sys.argv[1:2] == ["catalyst-modules"]:
        print("\n".join(CATALYST_MODULES))
    # `just spm-platform-test` asks for the schemes to test on a platform, which
    # `modules.py platform-test-schemes visionOS` writes and names.
    # `just spm-test-mac` and the xcodebuild test recipes ask what to skip: SwiftPM runs no
    # performance target (PERFORMANCE_TESTS).
    elif sys.argv[1:2] == ["swift-test-performance-skip"]:
        print(swift_test_performance_skip())
    elif sys.argv[1:2] == ["performance-targets"]:
        print("\n".join(performance_targets()))
    elif sys.argv[1:2] == ["platform-test-schemes"]:
        for name in TESTED_PLATFORMS[sys.argv[2]]:
            write(os.path.join(ROOT, ".swiftpm", "xcode", "xcshareddata", "xcschemes", f"{name}.xcscheme"), test_scheme(name))
            print(name)
    else:
        main()
