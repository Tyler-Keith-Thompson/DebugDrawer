# Installing the Drawer in a SwiftUI App

Attach the drawer to the root view of each window, register the global plugins at launch, and
open the drawer from a trigger the app chooses.

## Overview

The drawer is a view modifier, `debugDrawer()`, attached once at the root of the view hierarchy.
It draws the floating HUD and the toasts over the view it modifies, attaches the drawer's panel
to the window the view is in, and does nothing in release builds.

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
the window closes.

```swift
func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    // … the app's window …
    DebugDrawer.shared.attach(to: windowScene)
}
```

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

Each window has a drawer of its own, open or closed apart from the others;
``DebugDrawer/DebugDrawer/toggle()`` and ``DebugDrawer/DebugDrawer/isOpen`` act on the key
window's.

While the drawer is open, Cmd-K focuses its search field, Cmd-Option-Down and Cmd-Option-Up move
between plugins, and Escape clears the search, then leaves a plugin shown alone, then closes the
drawer. None of these exists while it is closed, so they never take a key from the app.

### Find a plugin

The drawer lists every plugin in sections with disclosure triangles, as Xcode's navigators do. A
section header's chevron, its Show Alone action, or the jump bar's menu shows one plugin alone at
the panel's full height, with the jump bar ending at it; the back button returns to the list.
Where the window is too narrow for a panel beside the app (an iPhone in portrait), the panel is as
wide as the window and opens at the list, and each row shows its plugin alone.

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

### Order the other modifiers around it

A modifier that changes the app's own views and not the drawer, such as the Accessibility
plugin's environment overrides, goes before `debugDrawer()`, so the drawer it adds keeps its own
look. A command that should also work while the drawer is open, such as tvOS's
`onPlayPauseCommand` to close it again, goes after it.
