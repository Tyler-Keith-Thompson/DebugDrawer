# Installing the Shipped Plugins

Install each shipped plugin with one call at startup, and see what the plugins with nothing to
configure show.

## Overview

Each shipped plugin installs itself with one call at startup. These are the install calls:

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
<doc:Modules> lists every module.

Tweaks takes the settings it shows, and Feature Flags the adapter it reads. Crash Reports, Hangs,
Leaks, MetricKit, Permissions, Notifications, Background Tasks, Analytics, Databases, File
Browser, UserDefaults, Localization, Screen Recording, Design Overlay, Color Vision and Reset App
State install through a type of their own. Each of those plugins, like Network's mocks and
conditions, is documented in its own module.

Some plugins need entitlements or Info.plist keys for part of what they show, and every plugin
that keeps a list bounds it; <doc:PluginRequirements> has both. The modifiers some plugins add to
the app's views are in <doc:InstallingInSwiftUI>, under "Order the other modifiers around it".

### The plugins with nothing to configure

These plugins need only their install call.

#### Performance

Performance counts the frame rate from a display link on the main run loop, so a blocked main
thread shows as dropped frames and a lower rate. It shows the memory footprint with its peak for
the process's life, CPU use per thread (the busiest eight until Show All) and a graph of the last
60 samples, one a second. On iOS, Simulate Memory Warning posts
`UIApplication.didReceiveMemoryWarningNotification` to the app's observers.

It samples only while a drawer shows its view or its HUD readout, from the plugin's
`didBecomeVisible(in:)` to its `didBecomeHidden(in:)`. The graphs keep their samples while it is
hidden and carry on from them.

#### Energy

Energy shows the battery's level, whether it is charging, the power source, the thermal state and
this process's CPU load, with two minutes of history. The CPU load is not Xcode's Energy Impact,
which also weighs the GPU, network, location and wakeups. Energy samples once a second while a
drawer shows its view, or between the app's own `EnergyMonitor.shared.start()` and `stop()`. A
Mac without a battery shows no Battery section.

#### Screenshot

Screenshot captures the app's key window. On macOS it captures the window's content, To Desktop
as a PNG named after the app and the time, or To Clipboard. On iOS it captures the window with
its sheets and alerts, to the clipboard. The drawer is a window of its own, so it is never in the
capture. The HUD is hidden while the capture is taken, and the drawer is closed for it unless its
switch says otherwise. A sandboxed Mac app that can't write to the Desktop gets a save panel
instead.

#### Keychain

Keychain lists the generic and internet passwords, certificates and keys the app can read, each
with every attribute the keychain returns, filtered by access group and text. A password's value
is read when its detail opens; a key's or certificate's data never is. Generic passwords can be
added and edited, on this device only, and any item can be deleted. On the Mac it reads the data
protection keychain, never the login keychain (<doc:PluginRequirements> has the entitlement it
needs there).

#### Loaded Libraries

Loaded Libraries lists every image loaded into the process when its view appears, grouped as App,
Third-Party (frameworks embedded in the app) and System. Each has its path, UUID, load address
and, for a framework, its version. The list has a filter and Copy List.

#### HTTP Cookies

HTTP Cookies lists `HTTPCookieStorage.shared`'s cookies by domain, read when its view appears and
on Refresh, and searched by name or domain. A row expands to its value, domain, path, store, flags
and expiry. Where WebKit exists (macOS and iOS; not tvOS or watchOS), it also lists the cookies
web views keep in `WKWebsiteDataStore.default().httpCookieStore`, and marks each row URLSession or
WKWebView by the store it is in.

Each cookie can be deleted from its own store. Delete All asks in place, then deletes the cookies
the filter shows; the count and Copy follow the filter too. Values are masked as the redaction
rules say, and by default those mask every cookie.

#### Launch Time

Launch Time measures from the process's start (from the kernel) to the `installLaunchTime()`
call, as pre-main, and from there to the first time the main run loop goes idle, as the first
frame. Call it as early as the app can: in `App.init` or
`application(_:didFinishLaunchingWithOptions:)`.

#### Accessibility

Accessibility overrides, for the views under `.debugAccessibilityOverrides()`, the color scheme,
Dynamic Type size, layout direction, the locale (when the app has localizations) and the
accessibility settings SwiftUI reads: Reduce Motion, Increase Contrast, Bold Text, Reduce
Transparency, Differentiate Without Color and Invert Colors, each beside the system's value.
Reset All clears them, and they last until the app quits. <doc:InstallingInSwiftUI> shows where
the modifier goes.

A release build gets none of this. There, a sidecar can override Dynamic Type, Increase Contrast
and Reduce Motion instead, through the `DebugDrawerAccessibility` module's receiver capability
(the DebugDrawerReceiver documentation's Overriding Accessibility Settings in Production article
covers it).

#### View Inspector

View Inspector outlines every AppKit or UIKit view in the app's windows, colored by its depth. It
draws the alignment grid over the views `.debugGrid()` is applied to and a ripple where each click
or touch lands, makes animations up to ten times slower, and lists the key window's view hierarchy
with each view's class and accessibility label.

The outlines, grid and ripples are drawn in a window of the drawer's own over the app's, which
takes no clicks or touches. They change no view or layer of the app's, and they don't appear in
the app's own snapshots or screenshots of its windows. A view's outline stops where something the
app shows covers it: a sheet, form sheet or popover presented over it, an opaque child window, or
an opaque window above its own. Slow Animations divides the speed of each window's root layer,
and gives back the speed it had at Normal. The View Inspector plugin's Counting Renders
article covers its render counts.
