# Browsing Databases

Open the app's SQLite, Core Data and SwiftData stores read-only, to check what the app saved.

## Overview

The Databases plugin finds the app's SQLite, Core Data and SwiftData stores and opens them
read-only, so a developer can check what the app wrote without copying the file off the device:

```swift
import DebugDrawerDatabaseBrowserPlugin

// At startup:
DatabaseBrowser.install()

// Or with folders of the app's own as well:
DatabaseBrowser.install(additionalDirectories: [URL.cachesDirectory.appending(path: "Databases")])
```

`DatabaseBrowser` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`.

### Finding stores

The plugin looks in Application Support, Documents, the containers of the app groups the app's
entitlements name, and `additionalDirectories`. It lists `.sqlite`, `.sqlite3`, `.db` and `.store`
files that begin with SQLite's header or are empty. `-wal`, `-shm` and `-journal` files belong to
their store and aren't listed apart. A Mac app outside the sandbox has only its own folder of
Application Support searched, and no Documents.

Each store shows its path, size, journal mode and kind. A Core Data or SwiftData store (one with
`Z_METADATA` and `Z_PRIMARYKEY`) lists its tables by entity name, with the `Z` table beneath, and
its model's version hash.

### Reading tables and queries

Opening a table pages its rows fifty at a time in a grid that scrolls sideways, with a search over
its text columns. NULLs, numbers, text and blobs (size and first bytes) are each drawn their own
way, and tapping a cell shows its whole value. The query editor runs one `SELECT` (or a pragma that
describes a table) and reads up to 200 rows. The page and the result copy as CSV.

### Read-only access

The browser only reads. It opens a store with `SQLITE_OPEN_READONLY`, sets `query_only`, and an
authorizer refuses anything but reading, so `INSERT`, `UPDATE`, `DELETE`, `ATTACH`, pragmas that
change the store and a second statement show as inline errors. A connection is open only while a
read runs, so the app's own writes and checkpoints are never held up for long. A store the app
holds locked shows "Store busy, try again". Reading a WAL store needs to write its `-shm` file; the
browser says when it can't.

The bug report carries `databases.txt`: each store with its tables and row counts, never their
rows. tvOS and watchOS have no pasteboard, so there the plugin offers no copy.
