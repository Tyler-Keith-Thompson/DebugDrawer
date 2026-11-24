# Editing UserDefaults

Browse and edit the standard defaults and app group suites, with values of every type.

## Overview

The UserDefaults plugin lists the keys of the standard defaults and of any suite the app names,
such as the app group suite it shares with its extensions:

```swift
import DebugDrawerUserDefaultsPlugin

// At startup:
UserDefaultsBrowser.install(suites: ["group.com.example.shared"])
```

`UserDefaultsBrowser` exists in every configuration and does nothing in release, so the call needs
no `#if DEBUG`. With suites named, a picker above the list switches between Standard and each
suite.

### Editing values

The list holds the keys the app wrote. Selecting one edits its value whatever its type:

- a string, number or data in a field (data in hex or Base64, as toggled);
- a Boolean as true or false;
- a date with a date picker;
- an array or a dictionary as a list of what it holds, where tapping an item drills in, however
  deep.

Text that isn't a value of the type says why under the field, and Save waits until it is. Each edit
writes the key's whole value back. Add Key adds a key of a chosen type, starting empty (a date
starts now), and an array or a dictionary takes items the same way.

### Following changes

The list follows the app's writes to any suite in the process as they happen
(`UserDefaults.didChangeNotification`). A write from another process, such as an extension's,
shows after Reload, in the menu beside Add Key. Show Other Domains, in the same menu, adds the
registered, launch-argument and global keys, each marked with where it comes from and read-only.
The bug report carries the standard defaults' keys as `user-defaults.json`.
