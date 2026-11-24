# Testing Deep Links

Send URLs, universal links and user activities to the app the way the system does, without
leaving it.

## Overview

Opening an https URL sends it to the browser, so you can't test a universal link, a Handoff or a
Spotlight result by opening a URL. The Deep Link Tester continues one in the app instead, as the
system does. An https URL in the field is sent as an `NSUserActivity` of type
`NSUserActivityTypeBrowsingWeb` with that `webpageURL`. Activity mode sends an activity of the
app's own type, with a userInfo of strings, numbers and Booleans. Sent activities are listed
separately from opened URLs, and tapping one puts it back in the form.

### Routing through the app's own code

Pass the code that routes the app's own URLs as `openURL`. An opened URL then goes to it instead
of the system, so it never reaches the browser or another installed copy of the app. It returns
whether it handled the URL, and the plugin shows which. A SwiftUI app's `onContinueUserActivity`
has no public entry point either, so a SwiftUI app also passes the code that handles an activity:

```swift
import DebugDrawerDeepLinkPlugin
import Foundation

/// The app's router: `onOpenURL` and `onContinueUserActivity` hand it the links the system opens.
@MainActor
final class Router {
    private(set) var path: [String] = []

    func handle(_ activity: NSUserActivity) {
        if let url = activity.webpageURL {
            path.append(url.path)
        }
    }

    func open(_ url: URL) -> Bool {
        guard url.scheme == "myapp" else { return false }
        path.append(url.path)
        return true
    }
}

let router = Router()

DebugDrawer.shared.installDeepLink(
    presets: DeepLinkPreset.bundleURLSchemes + [DeepLinkPreset("Order 42", url: URL(string: "myapp://orders/42")!)],
    continueUserActivity: router.handle,
    openURL: router.open
)
```

### Presets

Unless the app passes its own presets, Presets lists one URL for each scheme the app's Info.plist
declares under `CFBundleURLTypes` (`DeepLinkPreset.bundleURLSchemes`). With neither, it says how
to add some.

### Without the handlers

Without `openURL`, the system opens the URL as it would a tapped link, and the plugin says when it
couldn't and why. On the Mac, a scheme the app declares opens in the running copy of the app.

Without `continueUserActivity`, an activity goes where the system sends it in a UIKit or AppKit
app. On iOS that is the first window scene delegate with `scene(_:continue:)`, or else the app
delegate's `application(_:continue:restorationHandler:)`. On the Mac it is the app delegate's.
When the app has none of these, the plugin says so instead of dropping the activity.
