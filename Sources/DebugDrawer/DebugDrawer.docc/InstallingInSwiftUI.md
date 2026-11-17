# Installing the Drawer in a SwiftUI App

Attach the drawer to the root view of each window, register the global plugins at launch, and
open the drawer from a trigger the app chooses.

## Overview

The drawer is a view modifier, `debugDrawer()`, attached once at the root of the view hierarchy.
It draws the panel, the floating HUD and the toasts over the view it modifies, and does nothing
in release builds.

### Attach the drawer and register plugins

Attach `debugDrawer()` to the root view of the app's window group, and register the global
plugins once, at launch, under `#if DEBUG`:

```swift
struct OrdersApp: App {
    init() {
        #if DEBUG
            DebugDrawer.shared.registerGlobal(CachePlugin())
        #endif
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

### Open the drawer

The drawer binds no gesture or key of its own to open it. Call
``DebugDrawer/DebugDrawer/toggle()`` from whatever trigger suits the app: a triple tap, a
keyboard shortcut, a shake, or a button in its own debug menu.

```swift
struct OrdersRootView: View {
    var body: some View {
        Text("Orders")
            .onTapGesture(count: 3) {
                #if DEBUG
                    DebugDrawer.shared.toggle()
                #endif
            }
    }
}
```

While the drawer is open, Cmd-K focuses its search field, Cmd-Option-Down and Cmd-Option-Up move
between plugins, and Escape clears the search, then closes the drawer. None of these exists while
it is closed, so they never take a key from the app.

### Where the drawer appears

- **macOS, iOS and Mac Catalyst:** a panel along the window's trailing edge, over the app. Touches
  and clicks beside the open panel still reach the app.
- **visionOS:** an ornament beside the window, as tall as the window, covering none of the app.
- **tvOS:** the panel, driven by focus; Menu clears the search, then closes the drawer.
- **watchOS:** a full-screen list of the plugins, each row opening that plugin's view.

### Order the other modifiers around it

A modifier that changes the app's own views and not the drawer, such as the Accessibility
plugin's environment overrides, goes before `debugDrawer()`, so the drawer it adds keeps its own
look. A command that should also work while the drawer is open, such as tvOS's
`onPlayPauseCommand` to close it again, goes after it.
