# Browsing App Files

See what the app wrote to disk, how big it is and what is inside.

## Overview

The File Browser plugin lists the app's own folders, so a developer can see what the app wrote,
how big it is, and what is inside, without copying the container off the device:

```swift
import DebugDrawerFileBrowserPlugin

// At startup:
FileBrowser.install()

// Or with the containers of the app's groups as well:
FileBrowser.install(appGroups: ["group.com.example.orders"])
```

`FileBrowser` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`.

### Roots and sizes

The roots are Documents, Library, tmp, the app bundle and the shared container of each group in
`appGroups` (from `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`). A group the
system gives no container is listed as missing. A Mac app outside the sandbox shares those folders
with the user's other apps, so there the plugin lists the app's own folders of Application Support
and Caches instead of Documents and Library.

Every folder shows the total size of what it holds, at any depth, counted off the main thread and
stopped when you leave it. Folders and files show their size and their modified and created dates.

### Previews and actions

A file opens to a preview, chosen from its bytes rather than its name: text, JSON pretty-printed
with its keys sorted, property lists (binary or XML) as XML, and images as a thumbnail with their
pixel size. The first megabyte of text is read, and longer text says it is cut short. An image is
read whole, up to 64 MB. A SQLite file is listed like any other, with no preview.

A file can be shared, its path or text copied, and on the Mac revealed in Finder. Import… copies a
picked file into the folder shown. Rename… and Delete (which asks first) change a file or folder
anywhere but in the bundle, which is read-only.
