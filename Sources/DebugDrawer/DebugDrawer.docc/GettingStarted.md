# Getting Started

Add the package, write a plugin, attach the drawer to the app's root view and open it.

## Overview

DebugDrawer requires Swift 6.3. The drawer and the shipped plugins support macOS 15 and iOS 17
or later, Mac Catalyst included. This module also builds for visionOS 1, tvOS 17 and watchOS 10
or later, where an app registers plugins of its own.

### Add the package

Add the package, then the core and only the plugins you want to the app's target. Each plugin
is a library of its own:

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/DebugDrawer", from: "0.0.4"),
],
```

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "DebugDrawer", package: "DebugDrawer"),
    .product(name: "DebugDrawerConsolePlugin", package: "DebugDrawer"),
]),
```

### Write a plugin, attach the drawer, open it

A plugin is a title, an SF Symbol and a SwiftUI body. Register it globally, or attach it to the
view it belongs to; attach the drawer once to the root view; and open it from a trigger of your
own:

```swift
import DebugDrawer
import SwiftUI

struct CachePlugin: DebugDrawerPlugin {
    var title = "Cache"
    var icon = "trash" // an SF Symbol

    var body: some View {
        let usage = "\(URLCache.shared.currentDiskUsage / 1024) KB"
        DebugDrawerKeyValueRow("Disk usage", value: usage)
        DebugDrawerCopyButton("Copy Usage") { usage }
        Button("Clear URL cache") { URLCache.shared.removeAllCachedResponses() }
    }
}

// Global: registered once at startup, always in the drawer.
DebugDrawer.shared.registerGlobal(CachePlugin())

// The drawer, attached once to the root view.
let root = Text("Home").debugDrawer()

// Local: in the drawer while its view is on screen.
let settings = Text("Settings").debugLocalPlugin(CachePlugin())

// Open or close it from whatever trigger suits the app.
DebugDrawer.shared.toggle()
```

``DebugDrawer/DebugDrawer/shared`` exists in debug builds only, so the calls that name it sit
under `#if DEBUG` in an app. The plugin, `debugDrawer()` and `debugLocalPlugin(_:)` compile in
every build; <doc:ReleaseBuilds> lists what each does there.

### Next steps

- <doc:InstallingInSwiftUI> places the drawer in an app's scene and opens it from a gesture or
  a keyboard shortcut.
- <doc:WritingPlugins> covers the plugin protocol: global and local plugins, categories, search
  actions, badges, toasts and the HUD.
- <doc:BuildingPluginViews> lists the rows, buttons and styles plugins are built from.
- <doc:BugReports> adds a plugin's data to the bug report the drawer writes.
