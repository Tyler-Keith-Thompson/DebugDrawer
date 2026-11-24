# Overriding Accessibility Settings in Production

Let an accessibility reviewer try the shipping build at another Dynamic Type size, with Increase
Contrast or with Reduce Motion, without changing the device's settings.

## Overview

The reviewer sets the overrides from the sidecar, for the session. Link `DebugDrawerAccessibility`
(`.product(name: "DebugDrawerAccessibility", package: "DebugDrawer")`) beside the receiver, apply
the overrides to the app's root view, and enable the capability:

```swift
import DebugDrawerAccessibility
import DebugDrawerReceiver
import SwiftUI

@MainActor
final class ProductionAccessibilityReview {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.accessibilityEnvironmentOverrides())
        try receiver.start()
    }
}

struct ReviewedRoot: View {
    var body: some View {
        Text("Order history")
            .accessibilityEnvironmentOverrides()
    }
}
```

### The sidecar sets the values

The sidecar connects to `AccessibilityEnvironmentOverrides.pluginID`. The
`AccessibilityEnvironmentOverrides.Snapshot` holds each override (`dynamicTypeSize`,
`increaseContrast`, `reduceMotion`), `nil` while the system's value applies.
`setDynamicTypeSize(_:)`, `setIncreaseContrast(_:)`, `setReduceMotion(_:)` and `reset` change them,
within a session only. Outside one, or in an app that hasn't enabled the capability, they are
refused and audited.

### Session-scoped, always

As the session ends or expires every value is the system's again.

### SwiftUI views only

The modifier sets `dynamicTypeSize`, `colorSchemeContrast` and `accessibilityReduceMotion` in the
environment of the views under it, through SwiftUI's public modifiers and the settable keys previews
use, so a view that reads them, and every text style, follows. UIKit and AppKit views read the
system's settings and don't see the overrides.
