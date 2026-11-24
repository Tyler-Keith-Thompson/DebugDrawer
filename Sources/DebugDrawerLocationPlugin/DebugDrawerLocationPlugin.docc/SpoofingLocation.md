# Spoofing Location

Give the app a fixed coordinate or a route without leaving your desk.

## Overview

`installLocation()` swaps `CLLocationManager`'s location methods, so call it at startup, before
the app starts location updates.

With Spoof Location on and a coordinate typed, picked from the presets or played from a GPX route,
a manager that calls `startUpdatingLocation` gets that location instead of real updates, then each
new coordinate or route point as it changes. `requestLocation` and `location` answer with it too.
A manager that is already updating when spoofing begins stops getting real updates, and turning
spoofing off starts them again.

The switch and the coordinate are kept across launches, so spoofing is in effect from the next
launch's `installLocation()`. A coordinate out of range (latitude beyond ±90, longitude beyond
±180) isn't applied.

### What isn't spoofed

Only `CLLocationManager`'s location updates are spoofed. These still report the real location,
which on the iOS simulator is the one Xcode or `xcrun simctl location` sets:

- `CLLocationUpdate.liveUpdates()` and `CLMonitor`: no public API reaches what they yield.
- MapKit's user location (`showsUserLocation`, `UserAnnotation`, `MapUserLocationButton`).
- Region monitoring, significant-change and visit updates, and heading.

Authorization isn't simulated. `authorizationStatus` is the real one, and a spoofed location is
delivered whether or not the app is authorized.

### Release builds

The plugin is debug-only, and a release build swaps nothing. To spoof the location a production
build reads, during a sidecar's session, see the DebugDrawerReceiver
documentation's Spoofing the Location in Production article.
