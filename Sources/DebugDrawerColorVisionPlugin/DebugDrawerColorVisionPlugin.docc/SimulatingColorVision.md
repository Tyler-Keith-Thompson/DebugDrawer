# Simulating Color Vision

Find meaning carried by color alone by simulating color vision deficiencies over the app's views.

## Overview

The Color Vision plugin simulates protanopia, deuteranopia, tritanopia and grayscale over the
app's views while it runs. A designer can then see what carries meaning by color alone: an error
that reads like a success, chart series that merge.

```swift
import DebugDrawerColorVisionPlugin

struct ShopApp: App {
    init() {
        // At startup:
        ColorVision.install()
    }

    var body: some Scene {
        WindowGroup {
            OrdersView(orders: Order.samples)
        }
    }
}

// A screen's content, inside its ScrollView:
struct OrdersView: View {
    let orders: [Order]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Orders")
                    .font(.title)
                ForEach(orders) { order in
                    DeliveryBadge(isLate: order.isLate)
                }
            }
            .debugColorVision()
        }
    }
}

// In a List, each row's content:
struct OrderHistory: View {
    let orders: [Order]

    var body: some View {
        List(orders) { order in
            DeliveryBadge(isLate: order.isLate)
                .debugColorVision()
        }
    }
}

// A view whose colors carry meaning:
struct DeliveryBadge: View {
    let isLate: Bool

    var body: some View {
        Label(isLate ? "Late" : "On time", systemImage: "clock")
            .foregroundStyle(isLate ? .red : .green)
    }
}
```

`ColorVision` and `.debugColorVision()` exist in every configuration and do nothing in release, so
neither needs `#if DEBUG`.

### Choosing a simulation

The simulation is picked in the drawer from Off, Protanopia, Deuteranopia, Tritanopia and
Grayscale. It applies live to every view under `.debugColorVision()`, while the drawer, its HUD and
its toasts keep their colors. The plugin's header names the simulation that is on. Its HUD readout
(Show in HUD) moves to the next simulation with each tap, so they can be compared with the drawer
closed. Each launch starts with the app's own colors; `install(simulating:)` starts in a
simulation instead, for a launch argument of the app's own.

### How it draws

Each pixel is decoded to linear RGB, multiplied by the simulation's matrix and encoded again. The
three dichromacies use Machado, Oliveira and Fernandes's matrices (2009) at full severity, and
grayscale uses Rec. 709 relative luminance. The matrix runs as a Metal shader through SwiftUI's
`colorEffect`, which draws what SwiftUI draws.

A view that UIKit or AppKit backs (`List`, `Form` and `NavigationStack` on iOS, `ScrollView` on
macOS, text fields, maps, web views) shows SwiftUI's placeholder under it while a simulation is on.
So apply the modifier to a screen's content, inside its `ScrollView` or to each `List` row's
content, and not to the app's root. Leave controls that UIKit or AppKit draws outside it, such as
text fields, steppers, sliders and toggles.

For the whole screen, every view included, use the system's own color filters: Settings ›
Accessibility › Display & Text Size › Color Filters on iOS, and System Settings › Accessibility ›
Display › Color filters on macOS. The plugin's footer names them; it never turns them on.

With no simulation on, the modifier adds nothing, and the view draws exactly as it would without
it. Turning a simulation on or off draws the view anew, so the `@State` inside it starts over. The
plugin builds for macOS, iOS, Mac Catalyst, visionOS and tvOS; SwiftUI has no shaders on watchOS.
