# Resetting App State

Get a fresh install without deleting and reinstalling the app.

## Overview

The Reset App State plugin clears what deleting the app and installing it again would, without
doing either. Each kind of state has a checkbox with what it will delete beside it, a confirmation
lists everything, and the app can restart afterwards.

```swift
import DebugDrawerAppStateResetPlugin

// At startup:
AppStateReset.install()

// Or with the app's other stores, and a cleanup of its own:
AppStateReset.install(
    appGroups: ["group.com.example.orders"],
    directories: [URL.libraryDirectory.appending(path: "Exports")],
    cleanup: AppStateReset.Cleanup("Close the orders database") {
        OrdersDatabase.shared.close()
    }
)
```

`AppStateReset` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`, and a release build links no WebKit through it.

### Categories

Each category is cleared on its own:

| Category | What it deletes |
|---|---|
| UserDefaults | The keys of the app's domain and of each app group's suite, listed by name |
| Keychain | Every generic and internet password, certificate, key and identity the app can read, each by its persistent reference, listed by service and account or by label |
| Files | The contents of Documents, Application Support and tmp, each app group's container less its Library/Preferences and Library/Caches, and the `directories` given; never the directories themselves |
| Caches | The contents of Library/Caches, the app's and each app group's |
| Cookies | `HTTPCookieStorage.shared`'s cookies, and `WKWebsiteDataStore.default()`'s where WebKit exists, listed by domain |
| URL cache | `URLCache.shared`'s responses, its disk and memory use shown |
| App cleanup | The `cleanup` the app gave, run first, so it can close a database before its file goes |

### Resetting

Every category is read when the plugin is first shown, and again on Refresh, before anything is
deleted. Reset… opens the confirmation, which lists exactly what will go: each key, keychain item,
top-level file or folder with its size, and cookie domain. Reset deletes that and nothing else.

Reset and Relaunch then starts a new instance of the app on macOS and quits this one. An iOS, tvOS,
visionOS or Mac Catalyst app can't launch itself, so there the button is Reset and Quit, and the
app is opened again from the Home Screen (the Home View on visionOS, the Dock or the Finder in Mac
Catalyst). UserDefaults are written to disk and WebKit's cookie store is waited on before the app
ends. When something can't be deleted (a file in a folder that can't be written, an item the
keychain refuses), the app keeps running and the results name it and why.

### What stays

Links are deleted as links, never followed out of the container. App groups the entitlements name
are found on their own.

DebugDrawer's own state stays unless Include DebugDrawer's own settings is on. That state is:

- the drawer's own defaults suite (`<bundle identifier>.debugdrawer`: its layout, HUD pins and
  plugin settings);
- the keys starting `com.debugdrawer.` in the app's domain (Tweaks' values and Feature Flags'
  overrides);
- the files named `DebugDrawer…` in each directory and in its folder named after the app:
  recordings and mockups in `Caches/DebugDrawer` (or `Caches/<bundle identifier>/DebugDrawer` in a
  Mac app outside the App Sandbox), crash reports and MetricKit payloads.

### Platforms and the keychain

On iOS, tvOS and visionOS each app has a keychain of its own, and a query sees only the access
groups its entitlements name. On the Mac and in Mac Catalyst the plugin asks the data protection
keychain, which is scoped the same way, never the login keychain, whose items belong to every app
the user runs. An app without a keychain entitlement there gets `errSecMissingEntitlement`, which
the plugin shows, and nothing is deleted. A simulator build whose entitlements lack
`application-identifier` gets the same error; Xcode adds that entitlement and Bazel's rules_apple
doesn't.

A Mac app that isn't sandboxed shares Documents, Application Support, Caches and the temporary
directory with every other app, so there Files clears only Application Support's folder named after
the app, and Caches only the folder in Caches named after it. The plugin builds for macOS, iOS, Mac
Catalyst, visionOS and tvOS.

A production build resets the same categories from a sidecar. See the DebugDrawerReceiver
documentation's Resetting the App's State in Production article.
