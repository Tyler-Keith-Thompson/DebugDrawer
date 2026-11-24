# The Sidecar on Apple TV, Vision Pro, Apple Watch and Mac Catalyst

How the transports, the receiver and the kit work on each platform beyond iOS and macOS.

## Overview

The transports, the receiver and `DebugDrawerAppGroupContainer` build and run on every platform
the drawer does. The store is files in the app group's container and a dispatch source on its
directory, and every platform has both. Their tests run in the tvOS, visionOS and watchOS
simulators and for Mac Catalyst.

The kit itself (`DebugDrawerSidecarKit`) builds for iOS, iPadOS, macOS and watchOS, and on each
platform hosts the plugins that build there. On tvOS and visionOS, build a sidecar on
`DebugDrawerSidecarTransport` or `DebugDrawerAppGroupStoreTransport` directly, with views of its
own.

### Platform by platform

- Mac Catalyst follows iOS: a Catalyst sidecar and a Catalyst app share their group as iOS apps
  do. Catalyst apps aren't suspended, as on the Mac.
- visionOS follows iOS too, in its own windows. The sidecar opens beside the app, and both keep
  running while visible.
- tvOS has app groups, but only one app runs at a time. Switching to the sidecar suspends the app,
  and the background keeper's task lasts about 30 seconds (the Receiver documentation's Keeping
  the App Reachable in the Background article describes the keeper). So on Apple TV the sidecar works through the store: the
  app performs what the sidecar leaves there when it comes back to the foreground, and the sidecar
  reads the app's last snapshot meanwhile.
- watchOS: app groups don't span a watch and its iPhone, so a watchOS app's sidecar is a watch app
  on the same watch, signed by the same team and listing the same group. The watch sidecar needs
  nothing the iPhone one doesn't: it uses the same store, in the watch's own group container.

  Having the iPhone sidecar talk to the iPhone app and relay to the watch over WatchConnectivity
  was rejected for three reasons. It would put new code that carries
  commands into the production iPhone app, outside the trust boundary the app group draws. An
  independent watch app may have no iPhone app to relay through. And WatchConnectivity delivers a
  live message only while the other side is reachable, while its queued transfers arrive when the
  system chooses.

  A backgrounded watch app is suspended (the keeper holds nothing on watchOS), so it too picks up
  what the sidecar left when it comes to the foreground. The socket's tests pass in the watchOS
  simulator, but the simulator runs on the Mac's kernel, so on a watch rely on the store:
  `DebugDrawerSidecarTransport` uses it whenever the socket doesn't answer.

  A watch sidecar is built on `DebugDrawerSidecarKit`, like the iPhone's: the same
  `DebugDrawerSidecarView` in the watch app's `WindowGroup`, laid out for the way the watch
  navigates. The apps are a list, and each row opens the app's screen: its version and channel,
  its session with Open Session or End Session below it, a row per plugin it serves that opens the
  plugin, and Create Report.

  The kit hosts these capabilities' plugins on watchOS: `.featureFlagOverrides`,
  `.experimentOverrides`, `.logLevels`, `.tweaks`, `.localizationReview`,
  `.accessibilityEnvironmentOverrides`, `.analyticsEvents`, `.diagnosticsCapture`, `.bugReports`,
  `.scenarios`, `.authActions`, `.appStateReset`, `.environments`, `.userDefaults`,
  `.locationSpoofing` and `.appState`, plus any `DebugDrawerSidecarPlugin` of the company's own.
  Console, Network, Performance, MetricKit, Mocking and Push Registration (`.console`, `.network`,
  `.performanceTraces`, `.metricKitPayloads`, `.networkMocking`, `.pushRegistration`) don't exist
  on watchOS, because the modules they show don't build there. So a watch sidecar names the
  plugins it shows (`plugins` defaults to none). watchOS lets one app bring another forward only
  through the system's own URLs, so `DebugDrawerSidecarApp.open(url:)` returns `false` there, and
  Scenarios and Reset App State say to open the app instead:

  ```swift
  @main
  struct CompanyWatchSidecar: App {
      var body: some Scene {
          WindowGroup {
              DebugDrawerSidecarView(
                  groupIdentifier: "group.com.example.debug",
                  plugins: [.appState, .bugReports, .environments, .userDefaults]
              )
          }
      }
  }
  ```
