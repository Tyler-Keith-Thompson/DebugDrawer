# Reviewing Localization in Production

Let a translator show each string's key or pseudo-localized text on the build that ships, from the
sidecar, for the session.

## Overview

A translator can show each string's key, to name the one to fix, or pseudo-localized text, to find
what clips or was never translated. Link `DebugDrawerLocalization` (`.product(name:
"DebugDrawerLocalization", package: "DebugDrawer")`), the UI-free half of the Localization plugin,
beside the receiver. Read the strings a reviewer should see through `LocalizationReview`, and enable
the capability:

```swift
import DebugDrawerLocalization
import DebugDrawerReceiver
import SwiftUI

@MainActor
final class ProductionLocalizationReview {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.localizationReview())
        try receiver.start()
    }
}

struct SettingsHeader: View {
    let itemCount: Int

    var body: some View {
        VStack {
            Text(LocalizationReview.shared.localizedString("settings.title"))
            Text(LocalizationReview.shared.localizedString("\(itemCount) items"))
        }
    }
}

// The app's root view, redrawn as the mode changes:
// ContentView().localizationReview()
```

### The sidecar sets the mode

The sidecar connects to `LocalizationReview.pluginID`. The `LocalizationReview.Snapshot` holds the
mode (`standard`, `showingKeys` or `pseudoLocalized`), and `LocalizationReview.Command.setMode(_:)`
sets it, within a session only. Outside one, or in an app that hasn't enabled the capability, the
command is refused and audited, and every string shows its translation.

### Session-scoped, always

As the session ends or expires the mode returns to `standard`. A host can't keep it longer, since a
mode left on would show keys or accented text to whoever holds the device next.

### What it covers

It covers only strings the app reads through `LocalizationReview`:

- `localizedString(forKey:value:table:bundle:)`, which asks the bundle as
  `Bundle.localizedString(forKey:value:table:)` does;
- `localizedString(_:)`, which takes a `LocalizedStringResource` and resolves it as
  `String(localized:)` does, arguments and plural variant included, before the mode applies.

Show them in a SwiftUI `Text`, a UIKit label or anywhere else. `.localizationReview()` on the root
view gives it a new identity as the mode changes, so every body reads its strings again (and its
`@State` starts over). A UIKit screen observes `LocalizationReview.shared.$snapshot` and reloads its
text.

### What it doesn't cover

Nothing is intercepted in a release build, so the strings the app looks up any other way stay
translated: `Text("key")` and every `LocalizedStringKey`, `String(localized:)` and
`NSLocalizedString` called directly, storyboards and XIBs, `Info.plist` strings, and the system's
own text. A plural read through `localizedString(forKey:...)` loses its variants when
pseudo-localized; read it through `localizedString(_:)`.
