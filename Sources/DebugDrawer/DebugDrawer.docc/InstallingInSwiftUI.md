# Installing the Drawer in a SwiftUI App

Attach the drawer to the root view of each window, register the global plugins at launch, and
open the drawer from a trigger the app chooses.

## Overview

The drawer is a view modifier, `debugDrawer()`, attached once at the root of the view hierarchy.
It attaches the drawer to the window the view is in: the drawer's panel, the floating HUD and the
toasts, each drawn in a window of the drawer's own above the app's sheets and alerts. It does
nothing in release builds.

### Attach the drawer and register plugins

Attach `debugDrawer()` to the root view of the app's window group, and register the global
plugins once, at launch:

```swift
struct OrdersApp: App {
    init() {
        DebugDrawer.shared.registerGlobal(CachePlugin())
    }

    var body: some Scene {
        WindowGroup {
            OrdersRootView()
                .debugDrawer()
        }
    }
}
```

Mark the app's type `@main` as usual. Registering a plugin whose ID is already registered does
nothing, so a second registration of the same plugin is harmless.

### Attach the drawer in a UIKit or AppKit app

An app whose windows aren't SwiftUI's attaches the drawer itself: to each `UIWindowScene` once it
has connected, with `DebugDrawer.shared.attach(to: windowScene)`, or to each `NSWindow` with
`DebugDrawer.shared.attach(to: window)`. Attaching twice does nothing, so a SwiftUI view under
`debugDrawer()` in the same window is harmless. The drawer detaches when the scene disconnects or
the window closes. It is the same drawer `debugDrawer()` attaches, with every global plugin, the
floating HUD and the toasts.

```swift
func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    // … the app's window …
    DebugDrawer.shared.attach(to: windowScene)
}
```

#### When another framework makes the window

An app whose window and scene delegate come from another framework (a game engine, a renderer
written in another language that opens its own `UIWindow`) has no scene delegate of its own to
call `attach(to:)` from. Attach every connected `UIWindowScene` once the framework's window
exists, from a hook the framework calls at that point, and attach each scene that connects later
as it activates, on `UIScene.didActivateNotification`. The drawer's window sits above the
framework's view and passes through the touches it doesn't use.

```swift
@MainActor
final class DebugDrawerAttacher {
    static let shared = DebugDrawerAttacher()
    private var activation: (any NSObjectProtocol)?

    func attachEveryScene() {
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            DebugDrawer.shared.attach(to: windowScene)
        }
        guard activation == nil else { return }
        activation = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { notification in
            guard let windowScene = notification.object as? UIWindowScene else { return }
            MainActor.assumeIsolated { DebugDrawer.shared.attach(to: windowScene) }
        }
    }
}

// Called on the main thread by the framework's code once its window is open.
@_cdecl("orders_window_did_open")
public func ordersWindowDidOpen() {
    MainActor.assumeIsolated { DebugDrawerAttacher.shared.attachEveryScene() }
}
```

On the Mac, attach a window once it exists, such as when its window controller shows it:

```swift
final class OrdersWindowController: NSWindowController {
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        DebugDrawer.shared.attach(to: window)
    }
}
```

A local plugin belongs to the window its view is in, which `debugLocalPlugin(_:)` finds from the
SwiftUI view. A window with no SwiftUI view passes its window instead, to
`DebugDrawer.shared.registerLocal(_:in:)`: an `NSWindow` on the Mac, a `UIWindowScene` on iOS.
Only that window's drawer lists the plugin, which stays until the window closes or the scene
disconnects; the window needn't be attached yet. The call returns the token to pass to
``DebugDrawer/DebugDrawer/unregisterLocal(id:token:)`` to remove the plugin sooner, and a
registration of the same plugin ID for the same window replaces the earlier one.

```swift
final class CacheWindowController: NSWindowController {
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        DebugDrawer.shared.registerLocal(CachePlugin(), in: window)
    }
}
```

In a scene delegate, register once the scene has connected, with
`DebugDrawer.shared.registerLocal(CachePlugin(), in: windowScene)`.

### Open the drawer

The drawer binds no gesture or key of its own to open it. Call
``DebugDrawer/DebugDrawer/toggle()`` from whatever trigger suits the app: a triple tap, a
keyboard shortcut, a shake, or a button in its own debug menu.

```swift
struct OrdersRootView: View {
    var body: some View {
        Text("Orders")
            .onTapGesture(count: 3) {
                DebugDrawer.shared.toggle()
            }
    }
}
```

``DebugDrawer/DebugDrawer/open()`` and ``DebugDrawer/DebugDrawer/close()`` open and close it
outright, and do nothing if it is already so; use them where the trigger knows which it wants.
Read ``DebugDrawer/DebugDrawer/isOpen`` to know whether the key window's drawer is open, and
observe `$isOpen` for each change. Open and close the drawer with these calls; setting `isOpen` is
deprecated.

Some other triggers, including one for tvOS:

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

// Shake gesture with no responder of the app's own (iOS): the UIApplication subclass
// that Info.plist's NSPrincipalClass names, here "OrdersApplication"
@objc(OrdersApplication)
final class OrdersApplication: UIApplication {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake { DebugDrawer.shared.toggle() }
    }
}

// Play/Pause on the Siri Remote (tvOS), attached outside .debugDrawer() so it also closes it
ContentView()
    .debugDrawer()
    .onPlayPauseCommand { DebugDrawer.shared.toggle() }
```

A shake goes to the first responder and up the responder chain, so the `motionEnded` override
belongs on a responder the app owns, such as its window or a view controller. When another
framework owns every responder, the chain still ends at the application object: subclass
`UIApplication`, override `motionEnded(_:with:)` there, and name the subclass in Info.plist's
`NSPrincipalClass`. Under Bazel, mark the library that holds it `alwayslink = True`: only
Info.plist refers to the class, so the linker would otherwise drop it.

Each window has a drawer of its own, open or closed apart from the others;
``DebugDrawer/DebugDrawer/toggle()``, ``DebugDrawer/DebugDrawer/open()``,
``DebugDrawer/DebugDrawer/close()`` and ``DebugDrawer/DebugDrawer/isOpen`` act on the key
window's, as "Use the drawer with several windows" below describes.

While the drawer is open, Cmd-K focuses its search field, Cmd-Option-Down and Cmd-Option-Up move
between plugins, and Escape clears the search, then leaves a plugin shown alone, then closes the
drawer. None of these exists while it is closed, so they never take a key from the app.
<doc:UsingTheDrawer> lists the shortcuts and keyboard navigation in full.

### Use the drawer with several windows

An app with several windows on the Mac, or several scenes on iPadOS, has one registry of plugins
and one drawer per window. Each window's drawer opens and closes on its own, and lists the global
plugins and the local plugins of the views in that window only: a local plugin attached with
`debugLocalPlugin(_:)` in one window is not in another window's drawer.

``DebugDrawer/DebugDrawer/toggle()`` acts on the key window's drawer on the Mac (while the app
isn't active, the frontmost window's), and on iPadOS on the drawer of the scene holding the key
window, or else the foreground-active scene. To open or close the drawer in a window of your
choosing, pass it to `toggle(in:)`: an `NSWindow` on the Mac, a `UIWindowScene` on iOS. A window
or scene not attached yet is attached first, so the call works on its own in an AppKit or UIKit
app:

```swift
final class InvoiceWindowController: NSWindowController {
    @objc func toggleDebugDrawer(_: Any?) {
        guard let window else { return }
        DebugDrawer.shared.toggle(in: window)
    }
}
```

On tvOS, visionOS and watchOS the drawer is drawn in the app's own window, so there is one drawer,
which lists every local plugin.

### Find a plugin

The drawer lists every plugin in sections with disclosure triangles, as Xcode's navigators do. A
section header's chevron, its Show Alone action, or the jump bar's menu shows one plugin alone at
the panel's full height, with the jump bar ending at it; the back button returns to the list.
The panel is 316 points wide. Where the window is narrower than two of those (an iPhone in
portrait), the panel is as wide as the window and opens at the list, and each row shows its
plugin alone.

### Where the drawer appears

- **macOS:** a panel of its own, a child window along the trailing edge of the window it is
  attached to, above the window's sheets and alerts, an app-modal `NSAlert` included. Clicks
  beside it reach the app.
- **iOS and Mac Catalyst:** a window of the scene's own above the app's windows, its sheets and
  its alerts; touches beside the open panel fall through to the app.
- **visionOS:** an ornament beside the window, as tall as the window, covering none of the app.
- **tvOS:** the panel, over the app in the app's window, driven by focus; Menu clears the search,
  then leaves a plugin shown alone, then closes the drawer. A sheet or alert the app presents
  covers it.
- **watchOS:** a full-screen list of the plugins, each row opening that plugin's view.

<doc:SupportedPlatforms> covers the drawer on Apple TV and Apple Watch in more detail.

### Order the other modifiers around it

A modifier that changes the app's own views and not the drawer, such as the Accessibility
plugin's environment overrides, goes before `debugDrawer()`, so the drawer it adds keeps its own
look. A command that should also work while the drawer is open, such as tvOS's
`onPlayPauseCommand` to close it again, goes after it.

Some shipped plugins add a modifier of their own to the app's views. Each one goes above
`.debugDrawer()`:

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

<doc:ShippedPlugins> describes the plugins these modifiers belong to.
