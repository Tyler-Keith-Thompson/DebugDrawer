# Writing Global and Local Plugins

Write a tool of your own as a plugin, and register it for the app's lifetime or for as long as
one of its views is on screen.

## Overview

A plugin is a type that adopts ``DebugDrawerPlugin``: a ``DebugDrawerPlugin/title``, an
``DebugDrawerPlugin/icon`` (an SF Symbol's name) and a ``DebugDrawerPlugin/body``. Everything
else has a default. The drawer shows each plugin as a collapsible section with that title and
icon, and builds its body on the main actor, as SwiftUI builds a view's.

The protocol exists in every build, so a plugin compiles in release too, as long as its body
uses only API that does (<doc:ReleaseBuilds>).

### Global plugins

A global plugin stays in the drawer for the app's lifetime. Register it once, at launch, with
``DebugDrawer/DebugDrawer/registerGlobal(_:)``:

```swift
#if DEBUG
    DebugDrawer.shared.registerGlobal(CachePlugin())
#endif
```

Global plugins are listed by ``DebugDrawerPlugin/category``, a string a plugin may declare; one
that declares none is in `General`, listed last. The developer can pin a plugin to the top or
reorder it within its group from its header's context menu, and the drawer remembers that.

### Local plugins

A local plugin belongs to a screen: it is in the drawer while that screen's view is on screen,
listed above the global plugins. Attach it with `debugLocalPlugin(_:)`:

```swift
struct OrderPlugin: DebugDrawerPlugin {
    let orderID: String

    var title = "Order"
    var icon = "shippingbox"

    var contentIdentifier: String {
        orderID
    }

    var body: some View {
        DebugDrawerKeyValueRow("Order ID", value: orderID)
    }
}

struct OrderDetailView: View {
    let orderID: String

    var body: some View {
        Text("Order \(orderID)")
            .debugLocalPlugin(OrderPlugin(orderID: orderID))
    }
}
```

The modifier registers the plugin when the view appears and removes it when the view disappears.
A plugin that carries data the view changes declares a
``DebugDrawerPlugin/contentIdentifier`` that changes with it, here the order's ID; the modifier
registers the plugin again whenever it changes. When a new view registers a plugin with the same
ID before the old one disappears, the old view's disappearance leaves the new registration in
place.

### Identity

``DebugDrawerPlugin/id`` defaults to the type's name, which is what the drawer saves a plugin's
collapsed state, pin and order under. Declare an `id` of your own only to register several
instances of one type side by side.

### Search actions

The drawer's search field finds plugins by title, and runs the ``DebugDrawerAction``s a plugin
declares, each found by its title or keywords:

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
            }
        ]
    }
}
```

### Badges and toasts

A plugin can raise a problem while the drawer is closed. ``DebugDrawerPlugin/setBadge(_:)`` puts
a count on its header until ``DebugDrawerPlugin/clearBadge()``, and
``DebugDrawerPlugin/postToast(_:)`` shows a toast in the window's corner that opens the drawer at
the plugin when tapped. Posts from one plugin coalesce into one toast that counts them. These are
methods on the plugin, so they compile in release, where they do nothing.

```swift
let uploads = UploadsPlugin()
uploads.setBadge(2)
uploads.postToast("Upload of report.pdf failed")
uploads.clearBadge()
```

### A readout in the header or the HUD

A plugin can show something while its section is closed. Its
``DebugDrawerPlugin/headerAccessory`` sits at the trailing edge of its header row: a count of
what it found, a short summary, or a borderless action. Its ``DebugDrawerPlugin/hud`` is a
compact readout the developer can pin to the floating HUD, which stays on screen while the drawer
is closed.

```swift
struct JobsPlugin: DebugDrawerPlugin {
    var title = "Jobs"
    var icon = "gearshape.2"
    var category = "Background"

    var body: some View {
        Text("2 jobs failed")
    }

    var headerAccessory: some View {
        DebugDrawerIssueCount(.error, count: 2)
    }

    var hud: Text? {
        Text("2 failed")
    }
}
```

### Slow work

A body that reads a large file or scans a directory shouldn't block the main actor.
``AsyncPluginView`` runs its task when it appears and shows a progress indicator until the result
arrives; ``OnDemandPluginView`` waits for a button press first. Both exist in debug builds only,
so a plugin that uses them sits under `#if DEBUG`.

### A plugin's state

A plugin is a value the drawer reads, not a view, so it holds no `@State`. Keep a plugin's
state in a view its body returns, or in an observable store the plugin and the app share, and
pass the services it uses (storage, a clock, the network) in through its initializer, so a test
can hand it fakes.
