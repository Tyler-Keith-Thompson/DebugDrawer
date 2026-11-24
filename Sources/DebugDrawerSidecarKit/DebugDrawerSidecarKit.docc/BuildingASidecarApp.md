# Building a Sidecar App

Build your company's own sidecar app from the kit, under your own name, signing and app group.

## Overview

`DebugDrawerSidecarKit` is the sidecar app as a library. A company builds its own app from it,
under its own name, signing and app group, instead of installing one that DebugDrawer ships. One
view is the whole app:

```swift
import DebugDrawerSidecarKit
import SwiftUI

@main
struct CompanySidecar: App {
    var body: some Scene {
        WindowGroup {
            DebugDrawerSidecarView(groupIdentifier: "group.com.example.debug")
        }
    }
}
```

### How the sidecar finds apps

The sidecar app and the apps it reaches list the same group in their
`com.apple.security.application-groups` entitlement and keep their store in its `DebugDrawer`
folder (`DebugDrawerAppGroupContainer.storeDirectory`). The view's sidebar lists every app there
that serves a sidecar, with its name, version, build and bundle ID. That is a release build
running `DebugDrawerReceiver`, or a debug build running `DebugDrawerAppGroupStoreServer`.

Each app registers itself with a presence file in its own directory of the store
(`<store>/apps/<bundle ID>/presence.json`). The file holds its bundle ID, name, version, build, the
capabilities it serves, and the protocol version it speaks
(`DebugDrawerSidecarApp.protocolVersion`). The app writes it as it starts, rewrites it when the
capabilities it serves change and when it comes to the foreground, and removes it as it stops.
The list watches the store's `apps` folder and each app's folder and updates as the files change,
without polling. An app that was killed stays listed, with when it was last seen. An app whose
host has turned its receiver off (`DebugDrawerReceiver.isAllowed`) stays listed as turned off and
serves nothing.

### Several apps, one sidecar

A company with several apps can give its employees one tool for all of them. Each app of the group
serves its own directory of the store, `apps/<bundle ID>/`, which holds its presence file, its
socket, its snapshots (the sessions' among them) and the commands for it. The sidecar lists them
all and scopes every connection, session and file to the app picked. The directory comes from the
app's main bundle, never from a parameter. So one app's receiver or store server never performs
another app's commands and never serves where another app's sidecar reads, and it refuses a
command naming a capability that only another app serves (`commandRefused(.unknownCapability)`).

That is as far as the library can keep apps apart, because the system doesn't isolate apps
within one app group: any app of the group can read the whole container, including another app's
captured logs and requests. For real isolation, give each app an app group of its own and have the sidecar join
every one:

```swift
DebugDrawerSidecarView(groupIdentifiers: ["group.com.example.shop.debug", "group.com.example.wallet.debug"])
```

`DebugDrawerSidecarAppList(groupIdentifiers:)` and `init(storeDirectories:)` list several groups'
apps the same way. An app found in two groups is listed once, as it last registered. A group the
system gives no container is reported in `error`, and the other groups' apps are still listed.
Encrypting each app's files wouldn't help, because a key that both the app and the sidecar can
reach sits in the same container.

A store from before per-app directories (files at the top of `DebugDrawer/`) is neither read nor
removed. Each app writes its own directory the next time it starts serving.

### Connecting and opening a session

Picking an app connects to it with `DebugDrawerSidecarTransport`: live over its socket while it
answers, and through the store while it is suspended. For an app whose commands need a session
(one that serves `DebugDrawer.Sessions`), the detail shows the session's state with Open Session
and End Session. When the app's sessions require a signed grant, pass `grant`, which fetches one
from the company's server for the app picked. If it throws, the sidecar shows the error and opens
no session:

```swift
DebugDrawerSidecarView(groupIdentifier: "group.com.example.debug", sessionDuration: 10 * 60) { app in
    try await GrantService.shared.grant(for: app.bundleIdentifier)
}
```

### Plugins

Below the session, a picker shows the plugins the app serves, each drawn by the plugin's own view
over the transport. The defaults are `.console` and `.network` (a debug build's). The kit also has
a plugin for every capability the receiver ships, each named after its capability, and a sidecar
for production builds lists them:

```swift
DebugDrawerSidecarView(
    groupIdentifier: "group.com.example.debug",
    plugins: [
        .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview,
        .accessibilityEnvironmentOverrides, .analyticsEvents, .metricKitPayloads, .networkMocking,
        .diagnosticsCapture, .bugReports, .pushRegistration, .scenarios, .authActions, .appStateReset,
        .environments, .locationSpoofing, .userDefaults, .performanceTraces, .appState
    ]
)
```

A production app's receiver serves its capabilities only within a session. Until one opens, and
after it ends, each of its plugins shows "No Session" ("Open a session to see Flags.") in place of
data, and a plugin the session's grant doesn't list shows "Not Granted". A debug build's store
server serves at once, and its plugins show as soon as the app is picked.

The view shows only the plugins the picked app serves, so listing every one costs nothing for an
app that enables a few.

| Plugin | Capability | What the sidecar shows and sends |
|---|---|---|
| `.featureFlagOverrides` (Flags) | `.featureFlagOverrides` | Each flag with a switch, or a field and Set for a number or a string (only a value of the flag's kind), Clear, Clear All Overrides |
| `.experimentOverrides` (Experiments) | `.experimentOverrides` | Each experiment with a picker of its variants, which are forced and so excluded from analytics, Clear, Clear All Overrides |
| `.logLevels` (Log Levels) | `.logLevels` | Each subsystem with a picker of its levels, which are raised, Reset, Reset All Levels |
| `.tweaks` (Tweaks) | `.tweaks` | Each production-safe tweak with the control it declares (switch, picker, field and Set, stepper), Reset, Reset All |
| `.localizationReview` (Strings) | `.localizationReview` | The review mode: standard, pseudo-localized or keys |
| `.accessibilityEnvironmentOverrides` (Accessibility) | `.accessibilityEnvironmentOverrides` | Dynamic Type, Increase Contrast and Reduce Motion, each the system's or overridden, Reset |
| `.analyticsEvents` (Analytics) | `.analyticsEvents` | The session's events, newest first, with their properties as the app redacted them, Clear |
| `.metricKitPayloads` (MetricKit) | `.metricKitPayloads` | The payloads the app keeps, crash diagnostics among them, each with Copy JSON and Delete, Delete All; Create Report adds each as JSON |
| `.networkMocking` (Mocking) | `.networkMocking` | The hosts the app allows, the session's rules and delays with a switch and Remove, a form for a new rule (host, method, path, status, body) and one for a delay, Reset; `.networkMocking(presets:conditionPresets:)` adds the team's own as one-tap additions |
| `.diagnosticsCapture` (Diagnostics) | `.diagnosticsCapture` | Start Capture, then the app's lines and requests, Stop and Delete; Create Report adds `console.txt` and `network.json` |
| `.bugReports` | `.bugReports` | The app's reports, annotated, one picked for Create Report (see Reports and custom plugins) |
| `.pushRegistration` (Push Registration) | `.pushRegistration` | The device token with Copy Token, the APNs server, the notification settings, Refresh |
| `.scenarios`, `.authActions`, `.appStateReset`, `.environments`, `.locationSpoofing`, `.userDefaults`, `.performanceTraces`, `.appState` | the capability of the same name | As each capability's article in the Receiver documentation describes; the view hosts `.appState` as the app is reached, so every report carries it |

### Reports and custom plugins

A plugin of your own whose model adopts `DebugDrawerPluginModel` joins them through
`DebugDrawerSidecarPlugin(id:title:icon:snapshot:command:plugin:)`, whose closure makes the
plugin's view over the transport the kit hands it.

Create Report writes the hosted plugins' report contributions, redacted by
`DebugDrawer.shared.redaction`, under a summary naming the app picked, and offers Share. With
`DebugDrawer.shared.reportUploader` set, Send Report uploads it, as in the drawer.

### Building your own layout

For a layout of your own, the pieces are public:

- `DebugDrawerSidecarAppList`: the apps, as they come and go.
- `DebugDrawerSidecarConnection`: one app, with its channel, sessions, hosted plugins and
  `createReport(redaction:in:)`. Host `.appState` as the app is reached, to put the app's state in
  every report.
- `DebugDrawerSidecarApp`: one app, as its presence file describes it.

The kit builds for iOS, iPadOS and macOS, in debug builds. Like the transports it is built on, it
gets stand-ins in a release build that list no app, so archive a TestFlight sidecar in the Debug
configuration.

### Distributing it

The production app's team must sign the sidecar, because an app group belongs to one team.
TestFlight internal testers, a private Apple Business Manager app for your organization,
development or ad hoc signing, and on the Mac a notarized Developer ID app all keep it within your
team. An Apple Developer Enterprise Program account doesn't work, since it has another Team ID and
so no shared group. A public TestFlight link or an unlisted App Store app gives the sidecar to
anyone with the link. The Receiver documentation's Security Model and Distribution article has the
details, and what to do if the sidecar leaks.

### The example pair

`Example/Sidecar` is a sidecar built on the kit. Its app file lists the kit's plugins, and its
grant server stands in for a company's. `Example/Receiver` is the production app it drives: it
links only the receiver and the capability modules, and serves every capability the library
ships, within sessions that need a grant.

`just run sidecar` installs and launches both in the iOS simulator, in
`group.com.debugdrawer.example`, with the iOS example's debug build beside them in the same
group, so the sidecar lists two apps, each in its own directory of the store.
`just run sidecar macOS` launches the pair on the Mac. Pick the app in the sidecar and choose
Open Session. The sidecar's stand-in for a grant server signs a grant with RFC 8037's published
test key, which the host trusts. Each capability then has something in the host that changes:

| Sidecar plugin | What changes in the host |
|---|---|
| Flags | Checkout (`new-checkout`) and Button Color, through the host's `DebugDrawerFeatureFlagAdapter` |
| Experiments | Checkout Flow and Onboarding's variants, through the host's `DebugDrawerExperimentAdapter`, and Analytics, which reads "Excluded from" the forced experiments until they are cleared |
| Log Levels | The Checkout and Sync subsystems' levels, through the host's `DebugDrawerLogLevelAdapter`, and Last Written, the levels Log Checkout Step wrote lines at; back to `notice` as the session ends |
| Tweaks | The greeting, a production-safe tweak; the Diagnostics tweak isn't, so the sidecar never lists it |
| Strings | The Localization Review strings, pseudo-localized or shown as keys |
| Accessibility | The window's Dynamic Type, contrast and Reduce Motion, read back beside them |
| Analytics | Record Checkout Event's event appears in the sidecar, its `email` redacted |
| MetricKit | The payloads MetricKit hands the host on a device; Crash leaves a crash diagnostic for the next launch |
| Mocking | Add on the Mock Greeting preset (the example passes it to `.networkMocking(presets:conditionPresets:)`) answers the host's Fetch Greeting, and the host shows "Network mocking active"; the Slow Greeting delay holds the answer back two seconds |
| Bug Reports | Start Capture in Diagnostics and Log Sign-In, then Report a Bug in the host (or Feedback > Report a Bug, Shift-Command-B): the report appears in the sidecar with the window's screenshot, the line and the host's state, its email redacted; type an annotation, then Create Report, and Send Report with an uploader set; the session's end deletes it in the host |
| Diagnostics | Start Capture, then Log Sign-In and Fetch Greeting: the line and the request appear in the sidecar, the email, session ID and token redacted, and the host shows "Capturing diagnostics for a sidecar"; Create Report adds them to the report, and Stop and Delete or the session's end deletes them in the host |
| Scenarios | Open Order, Show Paywall and Onboarding Step, each with its parameters: Launch brings the host forward (its `debugdrawer-receiver-example://` scheme on iOS, its bundle identifier on the Mac) and opens the scenario's screen, such as "Order #456" |
| Auth | Expire Access Token, Force Token Refresh and Log Out: the host's Sign-In reads "Signed in, access token expired", "Signed in" or "Signed out" (Sign In signs in again), and the sidecar shows each action's result, such as "Failed: Not signed in"; the host's fake token is never shown or sent |
| Environment | Switch to Staging or Canary: the host's Environment section shows its title and base URL (kept in the host; the sidecar sees only IDs and titles) and the session indicator names the backend; back to Production as the session ends |

While the session is open, the host shows its own indicator: who holds the grant, until when, and
what keeps it running in the background, with End Session, and Keep Running on iOS. Its Sidecar
Allowed switch is the remote kill switch. Turning it off ends the session and reverts its changes.
On iOS the host is suspended once the sidecar is in front and the keeper's background task runs
out, so what the sidecar sends waits in the store until the host returns to the foreground.

On the Mac, a group named `group.` needs a provisioning profile, so `just run sidecar macOS` signs
both apps with your Apple Development identity into `<team ID>.com.debugdrawer.example`, a group
macOS gives them without asking. Signed ad hoc (no identity, or `DEBUGDRAWER_SIGN_IDENTITY=-`),
the apps get no group and share a folder in Caches instead, without a group container's
protection.

Launched with `-ScriptSession <bundle ID>` (`open -g /tmp/debugdrawer-example-sidecar/DebugDrawerSidecarExample.app
--args -ScriptSession com.debugdrawer.example.receiver`), the sidecar drives a session with that
app with no one at the screen. It opens a session with a grant, connects to the flags once the
session is open, overrides `new-checkout` to true, waits for the host to report it, and ends the
session. Then it opens a second session to read the flags back, waits for the flag to come back,
and ends that one too. It logs each step and the channel that carried it
(`log show --predicate 'subsystem == "com.debugdrawer.example.sidecar"'`), while the host logs its
audit entries (`subsystem == "com.debugdrawer.example.receiver"`). The receiver serves the store
only, so on the Mac too the channel is the store, and each command is performed as its file lands.
