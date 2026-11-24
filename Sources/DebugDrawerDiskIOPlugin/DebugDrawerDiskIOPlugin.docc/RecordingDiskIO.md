# Recording Disk I/O

See what the app reads and writes, and on which thread.

## Overview

`DebugDrawer.shared.installDiskIO()` records the app's file calls as they happen: each call's
operation, path, bytes, duration and thread, and the error of one that failed. Calls on the main
thread carry a warning. The totals (reads, writes, the bytes of each, main-thread calls and
failures) count every call since Clear, not only the 500 the list keeps.

Calls reach the drawer in batches, one per turn of the main queue, however many the app makes.
Pause drops the calls made until Resume, neither listing nor counting them. The Disk section shows
how full the home volume is and its free space, read when the plugin appears and on Refresh. The
list keeps the newest 500 calls; set `DiskIOStore.shared.capacity` for another number.

### What is recorded

The install alone puts swizzled methods in place, and they record:

- `FileManager`: `contents(atPath:)`, `createFile(atPath:contents:attributes:)`, `createDirectory`,
  `removeItem`, `contentsOfDirectory`, `copyItem` and `moveItem` (each by path and by URL), and
  `attributesOfItem(atPath:)`;
- `NSData`: `write(toFile:)` and `write(to:)` (with `atomically:` or `options:`), and its
  `contentsOfFile:` and `contentsOf:` initializers;
- `FileHandle`: the Objective-C reads and writes on regular files: `readData(ofLength:)`,
  `readDataToEndOfFile()`, `availableData`, `read(upToCount:)`, `readToEnd()` and `write(_:)`.

### What isn't recorded

On current OSes none of the following reaches a method the plugin can swizzle, so
`installDiskIO()` doesn't record it: Swift's `Data.write(to:)`, `Data(contentsOf:)` and
`FileHandle.write(contentsOf:)`, `String`'s file methods, POSIX calls (`open`, `read`, `write`),
SQLite, Core Data and `UserDefaults`. The unsafe install, described in the next section, records
the first four.

Also left out are a `FileHandle` call that fails, a call that Foundation makes inside a recorded
one, and the drawer's own file work: the File Browser's listings, bug reports, and the plugins'
saved settings and sessions. A plugin of your own marks its file work the same way, so it stays out
of the list:

```swift
let names = try DebugDrawerActivity.$isDrawerWork.withValue(true) {
    try FileManager.default.contentsOfDirectory(atPath: folder)
}
```

### Recording Swift's Data and FileHandle calls: an unsafe install

`DebugDrawer.shared.unsafeInstallDiskIOWithInterposing()` does what `installDiskIO()` does, and
also records Swift's `Data.write(to:)`, `Data(contentsOf:)` and `FileHandle.write(contentsOf:)`,
and `String`'s file methods. It records each `read`, `write`, `pread` and `pwrite` on a regular
file that no swizzled method records, with its path, bytes, duration, thread and error. A read that
reaches the end of a file, or a write of no bytes, moves nothing and isn't listed. A call to a
pipe, a socket or a terminal doesn't touch the disk and isn't listed either. The drawer's own work
stays out, as it does for the swizzled calls.

The app needs to link one more product, the `DebugDrawerDiskIOInterposer` dynamic library, which
holds dyld interposing tuples for those four functions:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "DebugDrawerDiskIOPlugin", package: "DebugDrawer"),
    .product(name: "DebugDrawerDiskIOInterposer", package: "DebugDrawer"),
])
```

In Xcode, add `DebugDrawerDiskIOInterposer` to the app target's Frameworks, Libraries, and
Embedded Content, embedded. The plugin never links it; the install looks it up at runtime. An app
that doesn't link it, or a build where dyld didn't load it at launch (a library opened with
`dlopen`, a plugin bundle, a test bundle SwiftPM loads), records what `installDiskIO()` records and
logs why. Before iOS 18 Foundation's Swift calls reach the `NSData` and `FileHandle` methods the
plugin swizzles, so there the install leaves interposing off. The library's functions pass every
call straight to the system until the install turns them on, and a release build's library holds
nothing.

#### Why it is unsafe

- dyld interposing is undocumented behaviour, which a new OS can change or drop without notice.
- An App Store build may be rejected for linking a library that uses it, so link it into debug
  builds only (a separate debug target, or a scheme that leaves it out of release).
- Once it is on, the plugin's code runs inside every `read` and `write` the process makes, on every
  thread, so a crash or a deadlock there takes the app with it.

dyld applies interposing only to a process it trusts. A debug build signed for development is one;
a hardened one may not be.
