# Checking Privacy Permissions

See every privacy permission the app declares and the status the system reports for it, to find
out why the camera doesn't work.

## Overview

The Permissions plugin lists every privacy permission the app's Info.plist declares a usage
description for, with the status the system reports for it now:

```swift
import DebugDrawerPermissionsPlugin

// At startup:
PrivacyPermissions.install()
```

`PrivacyPermissions` exists in every configuration, so the call needs no `#if DEBUG`. In release it
does nothing, and the plugin references none of the frameworks that report a status.

### What each permission shows

In debug builds each permission shows its name, its status (Allowed, While Using, Limited, Denied,
Restricted, Not Asked and so on, with a glyph for whether it grants access, partly or not), and the
usage descriptions that declare it with their keys:

| Permission | Keys | Platforms |
|---|---|---|
| Camera | `NSCameraUsageDescription` | iOS, macOS |
| Microphone | `NSMicrophoneUsageDescription` | iOS, macOS |
| Photos | `NSPhotoLibraryUsageDescription` | iOS, macOS |
| Photos (Add Only) | `NSPhotoLibraryAddUsageDescription` | iOS, macOS |
| Location | `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription`, `NSLocationUsageDescription` | iOS, macOS |
| Contacts | `NSContactsUsageDescription` | iOS, macOS |
| Calendars | `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`, `NSCalendarsUsageDescription` | iOS, macOS |
| Reminders | `NSRemindersFullAccessUsageDescription`, `NSRemindersUsageDescription` | iOS, macOS |
| Notifications | none needed | iOS, macOS |
| Tracking | `NSUserTrackingUsageDescription` | iOS, macOS |
| Motion & Fitness | `NSMotionUsageDescription` | iOS |
| Speech Recognition | `NSSpeechRecognitionUsageDescription` | iOS, macOS |
| Bluetooth | `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription` | iOS, macOS |
| Local Network | `NSLocalNetworkUsageDescription` (no status API: listed as declared) | iOS, macOS |
| Media & Apple Music | `NSAppleMusicUsageDescription` | iOS |

Notifications need no usage description, so every app may ask for them, and they are always
listed. Any other `NS…UsageDescription` key (Face ID, HealthKit) is listed too, marked as not
checked. A key declared on a platform without the permission is marked as not on it.

### Status, requests and Settings

A status is read again each time the app becomes active (as it does on coming back from Settings
or from a system prompt), when Location reports a change, and after a request. Nothing polls.

While the user hasn't decided, Request shows the system's prompt. If the request needs a key the
Info.plist lacks (Calendars and Reminders with only the legacy key, Location without the
when-in-use key), the plugin names the key instead. Open Settings opens the app's page in Settings
on iOS (its notification settings for Notifications), and the permission's pane under Privacy &
Security in System Settings on macOS.

A bug report carries `permissions.txt`: each permission, its status and its keys.
