# Identifying a Build

Show which build is running, what it runs on, and how it was signed.

## Overview

The first thing QA asks is which build this is. App Info answers with more than the version.

### Build

The Build section shows the version and build number. When the app supplies them, it also shows
the commit, branch and CI build number the build came from. Pass them at install, or write them
into the app's Info.plist (from a CI script, say) under `DebugDrawerGitCommit`,
`DebugDrawerGitBranch` and `DebugDrawerCIBuildNumber`. A value passed at install wins over the
plist's:

```swift
DebugDrawer.shared.installAppInfo(buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "release/2.4"))
```

The Build section also shows the bundle identifier.

### Runtime and Environment

Runtime comes next, with the memory footprint, uptime, process ID, architecture and argument
count. Then Environment: the OS, the sandbox (on the Mac), whether a debugger is attached, the
active processors, physical memory, the screen, the network path (Wi-Fi, cellular, Ethernet or
offline) and when the process started.

The footprint and uptime are read again every 2 seconds while a drawer shows the plugin, and not
at all while none does. The network path is watched from the plugin's first use, so Copy Info and
the bug report know it even with the drawer closed.

### Provisioning

Provisioning shows the embedded profile (`embedded.mobileprovision` on iOS,
`embedded.provisionprofile` on the Mac): its name, team, creation and expiry dates, and how many
devices it names. Once the profile has expired, it shows a warning. A simulator, App Store or
unprovisioned Mac build has no profile and shows None.

### Entitlements

Entitlements lists what the app runs with. The common ones appear by name (associated domains
first, then app groups, keychain access groups, the sandbox, get-task-allow) and the rest by key.
On the Mac they come from the code signature. On a simulator they come from the entitlements
linked into the executable. On a device they come from the profile, which gives what it allows.

### Copying and bug reports

Copy Info and the bug report's `App Info/app-info.json` carry all of this, with entitlements by
key.
