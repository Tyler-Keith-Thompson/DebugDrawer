# Resetting the App's State in Production

Get a production build back to a fresh install on an employee's own device, clearing defaults,
files, caches and cookies, without reinstalling it.

## Overview

The app allows the categories a sidecar may clear, the same ones the Reset App State plugin clears
in a debug build. The sidecar lists what each holds and confirms exactly that, and the app clears it
as it next comes to the foreground. The capability lives in `DebugDrawerAppStateReset`, which a
release build links beside the receiver (it links WebKit for the cookies; the receiver doesn't):

```swift
import DebugDrawerAppStateReset
import DebugDrawerReceiver

@MainActor
final class ProductionReset {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        try receiver.enable(.appStateReset(AppStateResetRequests(
            sessions: sessions,
            allowing: [.userDefaults, .caches, .urlCache, .cookies],
            launchURL: URL(string: "shop-internal://")
        )))
        try receiver.start()
    }
}
```

### The risk: data loss

A reset deletes what the app holds on the device it runs on, and it can't be brought back: a
tester's drafts, downloads and sign-in go with it. Allow only the categories a tester needs. An app
that allows only `.caches` (and `.urlCache`) lets a sidecar clear its caches and nothing else.
Consider `.requiringGrant()` on the capability, so only a sidecar your server vouches for may reset.

### Off by default

Until the app enables `.appStateReset(_:)`, a request is refused as
`commandRefused(.unknownCapability)`, even inside a session. A category the app didn't allow is
refused as `commandRefused(.notExposed)` and deletes nothing.

### App groups too

Files and Caches also clear the containers of the app's groups, except their preferences and the
receiver's store. Other apps of a group share its container, so a reset of one app deletes what they
keep there. Give the app a group of its own if that matters.

### The keychain only when asked for by name

`.all` holds every category but the keychain, and naming `.keychain` in `allowing:` traps. The app
allows the keychain with `allowingKeychain: true` alone, and then the listing names each item by its
service or label, never its account.

### The confirmation lists what will be deleted, and nothing else is

Nothing is read until the sidecar asks, in a session. The snapshot lists each category's keys,
top-level files and folders with their sizes, cookie domains and keychain services (at most 500 a
category, with a count of the rest), never a value.

A reset carries the categories confirmed and the revision of each that the confirmation showed. One
at another revision is refused as `commandRefused(.staleConfirmation)`. When what a category holds
changes before the reset runs, the app deletes nothing and reports the categories that changed. A
size changing doesn't count; a key, file, domain or item coming or going does.

### On the next foreground, then reported

A confirmed reset waits until the app is in the foreground, runs at once when it already is, and is
dropped when the session ends first or the app quits. The sidecar opens `launchURL` (on the Mac, the
app by its bundle identifier) to bring the app there. The snapshot's `lastReset` reports what each
category cleared, what it couldn't delete, and why. The app keeps running; restart it yourself if it
caches what was cleared.

### What stays

DebugDrawer's own state stays: the keys starting `com.debugdrawer.` or `DebugDrawer.` and the files
named `DebugDrawer…`. So does the receiver's store, so the session, its audit log and the sidecar's
view of the app survive the reset. A request is performed only in an open session and audited.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.appStateReset` lists the allowed categories with a checkbox each
and what each would clear. Review Reset… opens a confirmation listing every item, and Reset sends it
and then opens the app (`DebugDrawerSidecarApp.open(url:)`). While the reset waits for the app it
can be canceled; afterwards the plugin shows what was cleared.
