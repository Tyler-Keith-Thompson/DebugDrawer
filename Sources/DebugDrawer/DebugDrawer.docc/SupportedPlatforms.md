# Supported Platforms

Which modules build on which platforms, and how the drawer works on Mac Catalyst, visionOS,
Apple TV and Apple Watch.

## Overview

DebugDrawer requires Swift 6.3 and supports macOS 15 and iOS 17 or later. Every shipped plugin
builds for macOS and iOS.

The core module, `DebugDrawer` (the drawer, the plugin protocol and the shared views), also
builds for:

- visionOS 1 or later, where the drawer opens in an ornament beside the window instead of over it;
- tvOS 17 or later, where the remote's focus moves through it (see Apple TV, below);
- watchOS 10 or later, where it is a list of the plugins (see Apple Watch, below).

Analytics, Databases and Localization also build for visionOS, tvOS and watchOS, and Color
Vision and Reset App State for visionOS and tvOS. The other plugins build for macOS and iOS only,
so an app on another platform registers plugins of its own.

iOS includes Mac Catalyst: an iOS app built for the Mac shows the iOS drawer in its window. The
core and Analytics, Databases, Localization, Screen Recording, Design Overlay, Color Vision and
Reset App State build for Mac Catalyst.

### Apple TV

On tvOS the library binds no remote button, so the app opens the drawer itself, from a button in
its own interface or from a remote command it attaches, such as `.onPlayPauseCommand` or a long
press (`.onLongPressGesture`) on one of its views. Once open, the drawer takes focus, starting at
the plugin last used:

- Swiping or the arrows move focus through the header's buttons, the search field, each plugin's
  header and the controls inside an expanded plugin.
- Select on a plugin's header expands or collapses it; a long press shows its Pin, Move Up and
  Move Down actions.
- Select on the search field opens the keyboard. The results below the field are buttons.
- While focus is in the drawer, Menu clears the search if it holds text. Otherwise it returns
  from a plugin shown alone to the list, and otherwise it closes the drawer.

tvOS has no pasteboard and no share sheet. `DebugDrawerCopyButton` draws nothing there, and a bug
report names the zip's full path in the app's container instead of offering to share it. The HUD
stays at its corner, since tvOS has no drag.

### Apple Watch

A watch has no room beside the app, so on watchOS the drawer covers it. `toggle()` opens a
full-screen list of the plugins, grouped as on the other platforms (Local, Pinned, then each
category, with the pins and order the drawer saved). A row opens that plugin's view, which the
Digital Crown scrolls. The Close button closes the drawer, and opening a toast goes straight to
its plugin. The library binds no gesture, so the app opens the drawer from its own interface,
such as a button.

The watch list has no search, collapsing, pinning or Create Report; `createReport(in:)` can still
be called. watchOS has no pasteboard, so `DebugDrawerCopyButton` draws nothing there. It has no
context menus either, so a HUD readout leaves the HUD through `toggleHUD(forPlugin:)`.
