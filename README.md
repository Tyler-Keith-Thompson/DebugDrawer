# DebugDrawer

A plugin-based debug drawer for SwiftUI apps on macOS and iOS: a slide-in panel of debugging
tools, each its own library, so an app links only the tools it wants. Every entry point compiles
to a no-op outside `DEBUG`, so builds that ship to end users carry none of it.

## Installation

DebugDrawer requires Swift 6.4 and supports macOS 15 and iOS 17 or later, Mac Catalyst included.
The core also builds for visionOS, tvOS and watchOS, and so do some plugins
([Supported Platforms](Sources/DebugDrawer/DebugDrawer.docc/SupportedPlatforms.md)).

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
    // ... as many or as few as you need (Plugins, below)
]),
```

## Example

A plugin is a title, an SF Symbol and a SwiftUI body. Register it, attach the drawer once to the
root view, and open it from a trigger of your own:

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

None of this needs `#if DEBUG`. In release builds every call compiles and does nothing.

## Plugins

Each plugin is a product of its own, with its guide linked beside it.
[Installing the Shipped Plugins](Sources/DebugDrawer/DebugDrawer.docc/ShippedPlugins.md) shows
each one's `install*()` call, and [Modules](Sources/DebugDrawer/DebugDrawer.docc/Modules.md) lists
every module with what it holds.

- `DebugDrawerConsolePlugin`: `os_log` entries and your own logger's lines, filtered and kept across launches ([Console Sessions](Sources/DebugDrawerConsolePlugin/DebugDrawerConsolePlugin.docc/ConsoleSessions.md), [Filtering Console Lines](Sources/DebugDrawerConsolePlugin/DebugDrawerConsolePlugin.docc/FilteringConsoleLines.md), [Bridging Your Own Logger](Sources/DebugDrawerConsolePlugin/DebugDrawerConsolePlugin.docc/BridgingYourOwnLogger.md))
- `DebugDrawerNetworkPlugin`: HTTP requests and WebSocket frames, with mocks, slow networks, replay and HAR ([What the Network Log Captures](Sources/DebugDrawerNetworkPlugin/DebugDrawerNetworkPlugin.docc/WhatTheNetworkLogCaptures.md) and the other articles in its catalog)
- `DebugDrawerPerformancePlugin`: FPS, dropped frames, memory and CPU per thread
- `DebugDrawerEnergyPlugin`: battery, power source, CPU load and thermal state
- `DebugDrawerViewInspectorPlugin`: view borders, a grid, click indicators, animation speed and render counts ([Counting Renders](Sources/DebugDrawerViewInspectorPlugin/DebugDrawerViewInspectorPlugin.docc/CountingRenders.md))
- `DebugDrawerAccessibilityPlugin`: color scheme, Dynamic Type, layout direction, locale and accessibility settings overridden at runtime
- `DebugDrawerAppInfoPlugin`: build, provisioning, entitlements, OS and device facts ([Identifying a Build](Sources/DebugDrawerAppInfoPlugin/DebugDrawerAppInfoPlugin.docc/IdentifyingABuild.md))
- `DebugDrawerUserDefaultsPlugin`: UserDefaults keys of every suite, browsed and edited ([Editing UserDefaults](Sources/DebugDrawerUserDefaultsPlugin/DebugDrawerUserDefaultsPlugin.docc/EditingUserDefaults.md))
- `DebugDrawerKeychainPlugin`: keychain items and their attributes
- `DebugDrawerScreenshotPlugin`: the key window captured without the drawer
- `DebugDrawerFileBrowserPlugin`: the app's containers, with previews ([Browsing App Files](Sources/DebugDrawerFileBrowserPlugin/DebugDrawerFileBrowserPlugin.docc/BrowsingAppFiles.md))
- `DebugDrawerLocationPlugin`: spoofed locations and GPX routes ([Spoofing Location](Sources/DebugDrawerLocationPlugin/DebugDrawerLocationPlugin.docc/SpoofingLocation.md))
- `DebugDrawerLoadedLibrariesPlugin`: every loaded image, with UUIDs and load addresses
- `DebugDrawerDeepLinkPlugin`: URLs, universal links and user activities opened in the app ([Testing Deep Links](Sources/DebugDrawerDeepLinkPlugin/DebugDrawerDeepLinkPlugin.docc/TestingDeepLinks.md))
- `DebugDrawerCookiesPlugin`: HTTP and WebKit cookies
- `DebugDrawerLaunchTimePlugin`: pre-main and first-frame launch time
- `DebugDrawerTweaksPlugin`: the app's own debug settings ([Declaring Tweaks](Sources/DebugDrawerTweaksPlugin/DebugDrawerTweaksPlugin.docc/DeclaringTweaks.md))
- `DebugDrawerFeatureFlagsPlugin`: the app's feature flags, overridden locally ([Overriding Feature Flags](Sources/DebugDrawerFeatureFlagsPlugin/DebugDrawerFeatureFlagsPlugin.docc/OverridingFeatureFlags.md))
- `DebugDrawerCrashReportsPlugin`: the last crash, shown on the next launch ([Recording Crashes](Sources/DebugDrawerCrashReportsPlugin/DebugDrawerCrashReportsPlugin.docc/RecordingCrashes.md))
- `DebugDrawerHangDetectorPlugin`: main-thread hangs with their stacks ([Detecting Hangs](Sources/DebugDrawerHangDetectorPlugin/DebugDrawerHangDetectorPlugin.docc/DetectingHangs.md))
- `DebugDrawerLeakDetectorPlugin`: view controllers and objects that outlive their use ([Finding Leaks](Sources/DebugDrawerLeakDetectorPlugin/DebugDrawerLeakDetectorPlugin.docc/FindingLeaks.md))
- `DebugDrawerMetricKitPlugin`: MetricKit's payloads, kept across launches ([Keeping MetricKit Payloads](Sources/DebugDrawerMetricKitPlugin/DebugDrawerMetricKitPlugin.docc/KeepingMetricKitPayloads.md))
- `DebugDrawerPermissionsPlugin`: every privacy permission and its status ([Checking Privacy Permissions](Sources/DebugDrawerPermissionsPlugin/DebugDrawerPermissionsPlugin.docc/CheckingPrivacyPermissions.md))
- `DebugDrawerNotificationsPlugin`: the device token, notification settings and local pushes ([Testing Push Notifications](Sources/DebugDrawerNotificationsPlugin/DebugDrawerNotificationsPlugin.docc/TestingPushNotifications.md))
- `DebugDrawerBackgroundTasksPlugin`: BGTaskScheduler requests, scheduled and cancelled ([Launching Background Tasks](Sources/DebugDrawerBackgroundTasksPlugin/DebugDrawerBackgroundTasksPlugin.docc/LaunchingBackgroundTasks.md))
- `DebugDrawerAnalyticsPlugin`: the analytics events the app records ([Checking Analytics Events](Sources/DebugDrawerAnalyticsPlugin/DebugDrawerAnalyticsPlugin.docc/CheckingAnalyticsEvents.md))
- `DebugDrawerDatabaseBrowserPlugin`: SQLite, Core Data and SwiftData stores, read-only ([Browsing Databases](Sources/DebugDrawerDatabaseBrowserPlugin/DebugDrawerDatabaseBrowserPlugin.docc/BrowsingDatabases.md))
- `DebugDrawerDiskIOPlugin`: file calls, flagging main-thread I/O ([Recording Disk I/O](Sources/DebugDrawerDiskIOPlugin/DebugDrawerDiskIOPlugin.docc/RecordingDiskIO.md))
- `DebugDrawerLocalizationPlugin`: pseudo-localization, string keys and missing translations ([Testing Localization](Sources/DebugDrawerLocalizationPlugin/DebugDrawerLocalizationPlugin.docc/TestingLocalization.md))
- `DebugDrawerScreenRecordingPlugin`: a movie of the app without the drawer ([Recording the Screen](Sources/DebugDrawerScreenRecordingPlugin/DebugDrawerScreenRecordingPlugin.docc/RecordingTheScreen.md))
- `DebugDrawerDesignOverlayPlugin`: a design mockup over the app ([Comparing With a Mockup](Sources/DebugDrawerDesignOverlayPlugin/DebugDrawerDesignOverlayPlugin.docc/ComparingWithAMockup.md))
- `DebugDrawerColorVisionPlugin`: color blindness simulated over the app ([Simulating Color Vision](Sources/DebugDrawerColorVisionPlugin/DebugDrawerColorVisionPlugin.docc/SimulatingColorVision.md))
- `DebugDrawerAppStateResetPlugin`: the app's state cleared as a fresh install leaves it ([Resetting App State](Sources/DebugDrawerAppStateResetPlugin/DebugDrawerAppStateResetPlugin.docc/ResettingAppState.md))

Beyond the drawer:

- `DebugDrawerReceiver`: the one product a release build may link, serving an employee-only sidecar app within sessions ([Serving a Sidecar from a Production Build](Sources/DebugDrawerReceiver/DebugDrawerReceiver.docc/ProductionBuilds.md), [Security Model and Distribution](Sources/DebugDrawerReceiver/DebugDrawerReceiver.docc/SecurityModel.md))
- `DebugDrawerSidecarKit`: the sidecar app, as a library ([Building a Sidecar App](Sources/DebugDrawerSidecarKit/DebugDrawerSidecarKit.docc/BuildingASidecarApp.md), [Sidecar Sessions](Sources/DebugDrawerSidecarKit/DebugDrawerSidecarKit.docc/SidecarSessions.md), [A Device Lab](Sources/DebugDrawerSidecarKit/DebugDrawerSidecarKit.docc/DeviceLab.md), [Sidecar Platforms](Sources/DebugDrawerSidecarKit/DebugDrawerSidecarKit.docc/SidecarPlatforms.md))
- `DebugDrawerRemote`: a device's plugins viewed from a Mac over the local network ([Remote Viewing](Sources/DebugDrawerRemote/DebugDrawerRemote.docc/RemoteViewing.md))

## Documentation

The guides are DocC articles in each module's catalog. `just docs` builds them all into one site
in `.build/docs`. Start with these:

- [Getting Started](Sources/DebugDrawer/DebugDrawer.docc/GettingStarted.md): add the package, write a plugin and open the drawer
- [Installing the Drawer in a SwiftUI App](Sources/DebugDrawer/DebugDrawer.docc/InstallingInSwiftUI.md): the root view, UIKit and
  AppKit apps, several windows, and opening the drawer
- [Using the Drawer](Sources/DebugDrawer/DebugDrawer.docc/UsingTheDrawer.md): grouping, pinning, search, the HUD and the keyboard
- [Writing Global and Local Plugins](Sources/DebugDrawer/DebugDrawer.docc/WritingPlugins.md) and
  [Building a Plugin's View](Sources/DebugDrawer/DebugDrawer.docc/BuildingPluginViews.md): plugins of your own
- [Contributing to Bug Reports](Sources/DebugDrawer/DebugDrawer.docc/BugReports.md): reports, redaction and uploads
- [What the Plugins Need from the App](Sources/DebugDrawer/DebugDrawer.docc/PluginRequirements.md) and
  [Release Builds](Sources/DebugDrawer/DebugDrawer.docc/ReleaseBuilds.md)

To work on DebugDrawer itself, see `AGENTS.md`.

## License

MIT. See `LICENSE`.
