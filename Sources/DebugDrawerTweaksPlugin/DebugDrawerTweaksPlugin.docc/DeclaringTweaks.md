# Declaring Tweaks

Declare the app's own debug settings once and read each one anywhere, typed as declared.

## Overview

The Tweaks plugin shows the settings the app declares, in sections: toggles, pickers over an
enumeration or a list of strings, text fields, steppers and actions. Declare each tweak once, list
it in a section, and read it anywhere through `value`, typed as declared:

```swift
import DebugDrawerTweaksPlugin

enum Backend: String, CaseIterable {
    case production, staging, local
}

enum AppTweaks {
    static let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
    static let backend = Tweak.picker("Backend", key: "backend", default: Backend.production)
    static let greeting = Tweak.text("Greeting", key: "greeting", default: "Welcome")
    static let timeout = Tweak.stepper("Timeout (s)", key: "timeout", default: 30, in: 5 ... 120, step: 5)
}

DebugDrawer.shared.installTweaks {
    TweakSection("Features") {
        AppTweaks.newCheckout
        AppTweaks.greeting
    }
    TweakSection("Server") {
        AppTweaks.backend
        AppTweaks.timeout
    }
    TweakSection("Session") {
        TweakAction("Reset onboarding") {
            UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
        }
    }
}

// Anywhere in the app, in every build:
let url = switch AppTweaks.backend.value {
case .production: "https://api.example.com"
case .staging: "https://staging.example.com"
case .local: "http://localhost:8080"
}
```

### Storage and resetting

Values persist across launches in the standard `UserDefaults`, each key behind the prefix
`com.debugdrawer.tweaks.`. To keep them elsewhere, pass `installTweaks(storage:)` a
`UserDefaultsTweakStorage` with other defaults or another prefix, or a `TweakStorage` of your own.

A changed tweak has a button that resets it, and Reset All resets every tweak. A stored value that
is no longer one of a tweak's values (a removed case, a number outside a stepper's range) reads as
the default, or as the nearest bound. The drawer's search finds each action too.

### Following changes

To follow a tweak as it changes, subscribe to its `publisher`, which sends the current value
first:

```swift
struct CheckoutButton: View {
    @State private var isNewCheckout = AppTweaks.newCheckout.value

    var body: some View {
        Button(isNewCheckout ? "Check out (new)" : "Check out") {}
            .onReceive(AppTweaks.newCheckout.publisher) { isNewCheckout = $0 }
    }
}
```

### Release builds

`Tweak`, `TweakSection` and `TweakAction` exist in every configuration. Release has no drawer:
`value` is the declared default and `publisher` sends only that.

Mark a tweak `.productionSafe()` to let a sidecar app change it in a release build through the
receiver's tweaks capability, described in the DebugDrawerReceiver documentation's Changing Tweaks in
Production article. The drawer shows
the tweak the same way either way.

`Tweak`, its storage and its accessors live in `DebugDrawerTweaks`, a module with no UI that
`DebugDrawerTweaksPlugin` re-exports and that a release build links on its own.
