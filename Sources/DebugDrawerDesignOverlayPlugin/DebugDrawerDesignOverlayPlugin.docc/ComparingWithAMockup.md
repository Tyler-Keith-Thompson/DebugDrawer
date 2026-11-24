# Comparing With a Mockup

Lay a design comp over the running app to catch pixel drift.

## Overview

The Design Overlay plugin lays a design comp over the running app, to catch pixel drift. The comp
is drawn at an opacity, an offset and a scale, normally or in a difference blend.

```swift
import DebugDrawerDesignOverlayPlugin

struct ShopApp: App {
    init() {
        // At startup:
        DesignOverlay.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .debugDesignOverlay() // beneath .debugDrawer(), so the mockup lies under the drawer
                .debugDrawer()
        }
    }
}
```

`DesignOverlay` and `.debugDesignOverlay()` exist in every configuration and do nothing in release,
so neither needs `#if DEBUG`.

### Picking the mockup

The mockup is picked in the drawer: from Photos or Files on iOS and Mac Catalyst, and from a file
or the pasteboard (an image, or an image file copied in the Finder) on macOS. Photos runs out of
the app's process, so nothing asks for a permission. The mockup is kept in
`Caches/DebugDrawer/DesignOverlay` (in a Mac app outside the App Sandbox,
`Caches/<bundle identifier>/DebugDrawer/DesignOverlay`) with its settings, so it is there again on
the next launch, until Clear. `DesignOverlay.install(mockup:)` takes an image's data instead, for a
comp the app bundles or generates. That comp is shown for that launch without replacing the saved
one.

### Placing it

The mockup is drawn from the window's top-leading corner, under the safe area, as a screen's
mockup is. Automatic infers whether it was exported at @1x, @2x or @3x from its width against the
window's, and Fit Width, @1x, @2x and @3x set the scale. Opacity runs from 5% to 100%. Difference
draws black where the app matches the mockup and bright where it drifts.

The X and Y steppers move the mockup a point at a time. With Move by Dragging on, a drag anywhere
in the window moves it, and a bar at the bottom leading corner shows the offset and Done. Outside
Move the mockup takes no touches or clicks, so the app under it keeps working.

The plugin's header shows the opacity and blend, "Hidden" or "Moving". Its HUD readout (Show in
HUD) hides and shows the mockup with the drawer closed, or ends Move. The mockup belongs to the
app's content, so screenshots and screen recordings include it.
