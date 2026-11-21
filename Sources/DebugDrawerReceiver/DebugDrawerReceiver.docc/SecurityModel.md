# Security Model and Distribution

What the receiver trusts, what someone holding the sidecar can do with each capability, and how
to get the sidecar to your employees and no one else.

## Overview

A production app that links ``DebugDrawerReceiver`` can be driven by a sidecar app: an
employee-only app your company builds from `DebugDrawerSidecarKit`, signed by the same team and
sharing an app group with the production app. This article is the threat model for that pair.
It covers release builds; a debug build's drawer is the developer's own and isn't gated.

The short version:

- **The app group is the boundary.** Whatever can read and write the group's container can act
  as the sidecar. The receiver doesn't check who wrote a command; the system decides who reaches
  the container.
- **The receiver only affects the device it runs on.** The store is files on that device. A
  sidecar that leaks lets whoever installs it change their own copy of your app, not anyone
  else's.
- **Nothing is on until the host turns it on.** Every capability is off until the app enables
  it, each takes only the values the app declares, and its changes are scoped to a session that
  expires.
- **The layers on top are yours to add.** Signed grants say who may open a session, a remote
  gate shuts every sidecar out without a release, and the audit log records what was done.

## The trust boundary

### What lets a sidecar in

The receiver reads commands from, and writes snapshots to, its own directory of the group's store,
`DebugDrawer/apps/<bundle ID>/` in the app group's container. It doesn't serve the socket a debug
build serves. A command is a file there, and the receiver performs any command file it finds: it
doesn't check the writer's code signature, and it has no way to tell the sidecar from another
process that can write the container. What keeps others out is the system's control of the group
container:

- **iOS, iPadOS, tvOS, visionOS and watchOS.** An app reaches a group's container only when its
  signed entitlements list the group, and an app group belongs to the developer team that
  registered it. So the apps that can read or write the store are your team's apps that list the
  group, and the system checks that, not the library.
- **macOS.** The receiver needs macOS 15 or later, where the system also protects group
  containers. An app signed by the team that owns the group reaches it without being asked: a
  group named with the team ID prefix (`TEAMID.com.example.debug`), or a `group.` one listed in a
  provisioning profile. Another app that touches the container makes macOS ask the person whether
  it may access data from other apps, and if they allow it, that app can read and write the
  store too. The receiver and the transports throw `accessDenied` when the system refuses them,
  and write nothing. A Mac container is therefore weaker than an iOS one: it holds against apps
  the person doesn't approve, not against the person. Which other processes macOS exempts from
  the prompt (tools given Full Disk Access, for example) isn't verified here; assume any process
  running as the signed-in user may be allowed in.

The bundle ID that names the receiver's directory comes from the main bundle, never a parameter,
so two apps of one group never perform each other's commands. That is as far as the library can
keep them apart: **the system doesn't isolate apps within one group**. Any app of the group can
read the whole container (another app's snapshots, captured logs, push token and reports
included) and write commands into any app's directory. For real isolation, give each app a
group of its own and have the sidecar join every one
(`DebugDrawerSidecarView(groupIdentifiers:)`).

### What the receiver checks itself

Inside the boundary, a command meets these checks, in this order:

1. **The host's gates.** ``DebugDrawerReceiver/isAllowed`` first, before the command is decoded
   or any grant is read, then the capability's own gate from
   ``DebugDrawerReceiver/enable(_:isAllowed:)``.
2. **Default-deny.** A command to an ID no enabled capability holds is refused as
   `unknownCapability`, and with nothing enabled even opening a session is refused.
3. **The session.** A command lands only while a session is open; it expires at the host's
   maximum, or the grant's expiry, at the latest.
4. **The grant**, when the sessions have a ``DebugDrawerGrantPolicy`` or the capability is
   ``DebugDrawerReceiverCapability/requiringGrant()``: the session's grant must list the
   capability.
5. **The capability's own vocabulary.** The command decodes into the capability's `Command` type
   or is refused as `malformedCommand`; then the model refuses a key, value, variant, scenario,
   category or host it doesn't list (`notExposed`, `malformedCommand`). Nothing received is run
   or evaluated: a sidecar picks among what the app declared, and the app's own code does the
   rest.

Every outcome, applied or refused, is written to the audit log.

### Outside the model

- A jailbroken device, or a Mac account an attacker already controls: either can read and write
  the store without the sidecar, and the app with it.
- Someone holding an unlocked device: they can use the sidecar installed on it, as its owner can.
  The session indicator (below) is what tells the person holding the device that tooling is
  engaged.
- Attacks on the company's grant server, its SSO, or the remote configuration behind the gates:
  the library trusts what they say.

## Default-deny

The receiver acts on nothing until the app enables a capability with
`receiver.enable(...)`, and acts on a capability only within the values the app declared for it:
the flags its adapter lists, the experiments and their variants, the UserDefaults keys and their
kinds, the environments in its allowlist, the hosts a mock may answer, the readings it passes
through location spoofing. That is what keeps a
leaked sidecar from doing more than the app chose to offer, and why a capability added to the
library reaches no app until that app enables it.

Snapshots are what the capability's model puts in them, and they are in the store only while a
session may read them ("What a sidecar can read, and when"). The receiver removes, as it starts,
every snapshot file but the sessions', so nothing an earlier launch wrote, a launch killed during a
session included, stays readable.

## Sessions

A sidecar opens a session by sending `open(duration:grant:)` to ``DebugDrawerSessions/pluginID``.
One is open at a time, and it lasts the duration asked for, the sessions' maximum or the grant's
expiry, whichever comes first. A command after the expiry date never lands, even before the
system's timer fires in an app that was suspended.

As the session ends, expires, or the receiver's gate turns off, every session-scoped change is
reverted and audited as `changeReverted`; a capability's own gate turning off reverts that
capability's change at once. Persistent changes stay. Sessions live in memory, so a session the
app was killed in never ends on its own. The capabilities whose state outlives the process keep a
record of what they changed and revert it as the next launch makes or enables them, so make every
capability at startup. Feature flags, experiments, log levels, environments, location and
UserDefaults keep theirs in the app's own defaults, beside the change. For the rest (tweaks
enabled with a session scope, a model of the app's own enabled with `.model(_:id:scope:)` and a
session scope) the receiver keeps one in the app's directory of the store,
`unreverted-changes.json`: each capability a session changed and the session's ID, written before
the change is applied and cleared once it is reverted, so a kill at any point leaves at worst one
revert that finds nothing to put back. As the next launch enables the capability, it performs the
scope's command and audits `changeReverted` in the session that made the change; a capability that
launch doesn't enable keeps its entry until one does. Whatever can write the container can add an
entry, making the next launch perform a capability's session revert, or remove one, so that a
change a killed session left stays until the next session's revert; it can't make the receiver run
anything else.

## The session indicator

The library draws no indicator: drawing one is the host's job, and it should. Observe
``DebugDrawerSessions/snapshot`` and show, for as long as a session is active, that debug tooling
is engaged, until when, who holds the grant (``DebugDrawerSession/grant``) and an End button that
calls ``DebugDrawerSessions/end()``. Add what changes what the person sees: the backend from
``DebugDrawerEnvironments/Snapshot/isSwitched``, "Network mocking active" from `NetworkMocking`'s
`snapshot.isActive`, the spoofed location from `LocationSpoofing`'s `snapshot.coordinate`, "Capturing diagnostics" from
``DebugDrawerDiagnosticsCapture/Snapshot/isCapturing``. On iOS 26 and later,
``DebugDrawerBackgroundKeeper/startSession(duration:title:subtitle:)`` also gets the system's own
progress indicator; elsewhere the app's indicator is the only one.

## The audit log

``DebugDrawerSessions/auditLog`` keeps the newest entries (1,000 by default) in memory, and
``DebugDrawerSessions/auditEntries`` publishes every entry as it is recorded. Each
``DebugDrawerAuditEntry`` holds the date, the session's ID, the capability's ID and the event:
`sessionOpened(expires:grant:)` (naming the grant by its ID and subject, never the token),
`sessionEnded`, `commandApplied`, `commandRefused` with the reason, or `changeReverted`.

It never holds what a command carried, with one exception: an allowlisted UserDefaults edit and
its revert carry ``DebugDrawerAuditEntry/changes``, the key and its value before and after, so
never allowlist a secret. Snapshot reads aren't audited: the log records what a sidecar did, not
what it read. The log isn't written to disk, so what the host hasn't forwarded is lost when the
app quits; forward ``DebugDrawerSessions/auditEntries`` to your own log or server if you need a
record that lasts.

## Signed grants

Team signing and the app group keep other companies' apps out, but not a sidecar build that
reached the wrong person. Grants are an optional layer: the sidecar signs the employee in with
your SSO and gets a short-lived grant from your server, listing the capabilities that person may
drive and when it expires; the app verifies it with a public key it embeds
(``DebugDrawerSignedGrantVerifier``, Ed25519 or P-256), or with a verifier of your own.

With a ``DebugDrawerGrantPolicy`` on the sessions, a session opens only with a grant for the
app's bundle ID that is valid now and hasn't opened one before; it ends at the grant's expiry at
the latest; and a command to a capability the grant doesn't list is refused as
`capabilityNotGranted`. Without a policy, ``DebugDrawerReceiverCapability/requiringGrant()`` on a
capability makes it unusable, as no session then has a grant; network mocking always requires
one. What a grant can't do:

- **Survive a relaunch as single-use.** Grant IDs already used are remembered in memory until the
  grant expires, so after a relaunch a grant copied from the store (it travels in the command
  file that opens the session) could open one more session. Issue grants that last minutes.
- **Hide what a session reads from another app of the group.** Under a policy a session reads
  only the snapshots of the capabilities its grant lists, but while it is open those files sit in
  the shared container, where any app of the group can read them too (see "What a sidecar can
  read, and when").

## The remote kill switch

Back ``DebugDrawerReceiver/isAllowed`` with your own remote configuration, and call
``DebugDrawerReceiver/reevaluateGates()`` as it changes. While it returns `false` every command is
refused as `receiverDisabled`, the open session ends as `disabledByHost` and reverts its
session-scoped changes, every capability's snapshot leaves the store, and the presence file lists
no capability, so a sidecar shows the app as turned off. A capability's gate
(``DebugDrawerReceiver/enable(_:isAllowed:)``) does the same for one capability while the session
goes on. The library calls no configuration service and doesn't poll; the receiver asks the
gates at each command, as it starts, as the app comes to the foreground and before each snapshot
it writes. This is how you shut out a leaked sidecar without a release.

## What a sidecar can read, and when

The store sits in a container every app of the group can read, and a read of a file there can't be
observed or audited, so the receiver keeps a capability's data out of it except while a sidecar
could act on it:

- **No session open: nothing.** The app's directory holds its presence file (who the app is, the
  IDs it serves, the protocol it speaks), the sessions' snapshot (no session, or the open one's ID,
  two dates and its grant's claims, never the token) and `unreverted-changes.json` while a killed
  session's change waits for its revert (capability and session IDs, no value). No capability's
  snapshot is written: not the flags and their values, the experiments and their assignments, log
  levels, tweaks, environments, allowlisted UserDefaults, scenarios, auth actions, review modes,
  network mocking's allowed hosts, a spoofed coordinate, or any other.
- **A session open: what it may read.** As a session opens, the receiver writes each enabled
  capability's snapshot before the sessions' own snapshot says the session is open. Under a grant
  policy, and for a capability made ``DebugDrawerReceiverCapability/requiringGrant()``, only the
  capabilities the session's grant lists are written; without a policy every one that doesn't
  require a grant is.
- **Removed as the session ends.** Each snapshot leaves the store as the session ends, expires
  (when its timer fires: an app suspended past the expiry removes them as it resumes), the
  receiver's gate or the capability's turns off, the capability is disabled, the receiver stops,
  and, for what a launch killed during a session left, as the next launch starts the receiver,
  before it serves anything.
- **Collected only for a session.** Diagnostics capture, bug reports, performance traces and the
  app state reset listing also hold nothing until a sidecar asks within a session; analytics
  events, MetricKit payloads, the push registration and the app state snapshot hold nothing for a
  session whose grant doesn't list them.

While a session is open, any app of the group can read what it reads. So list in an adapter or
allowlist only what you're content for the group's apps to read during a session, keep sessions
short, and give an app that shares a group with apps you don't trust a group of its own.

## Threat model

Each capability below says what someone holding the sidecar, a leaked copy included, can do to
the app on the device the sidecar is installed on, what they can't, and how the host limits it.
Every one is off until the app enables it. In the Grant column, "Under a policy" means its
commands, and its snapshot, need a grant that lists it when the sessions have a
``DebugDrawerGrantPolicy``; any
capability also takes ``DebugDrawerReceiverCapability/requiringGrant()`` to need one in every
receiver, as network mocking always does.

| Capability | Risk | Scope | Grant |
|---|---|---|---|
| Feature flag overrides | Medium | Session by default, or persistent | Under a policy |
| Experiment overrides | Low | Session by default, or persistent | Under a policy |
| Log levels | Medium | Session, always | Under a policy |
| Diagnostics capture | Medium | Session, always | Under a policy |
| Bug reports | Medium | Session, always | Under a policy |
| Scenarios | The handlers' | Persistent (can't be undone) | Under a policy |
| Auth actions | Low | Persistent (can't be undone) | Under a policy |
| Environments | High | Session, always | Under a policy |
| Allowlisted UserDefaults | Medium | Session by default, or persistent | Under a policy |
| Tweaks | The tweaks' | Persistent by default, or session | Under a policy |
| Analytics events | Low | Nothing to revert | Under a policy |
| Localization review | Low | Session, always | Under a policy |
| Accessibility overrides | Low | Session, always | Under a policy |
| Crash reports and MetricKit payloads | Low | Persistent (deletions) | Under a policy |
| Network mocking | High | Session, always | Always |
| Location spoofing | High | Session, always | Under a policy |
| Push token | Low to medium | Nothing to revert | Under a policy |
| App state reset | Medium (data loss) | Persistent (can't be undone) | Under a policy |
| Performance traces | Low | Session, always | Under a policy |
| App state snapshot | Low | Nothing to revert | Under a policy |
| A model of the app's own | The model's | The host's choice | Under a policy |

### Feature flag overrides

``DebugDrawerFeatureFlagOverrides`` (`.featureFlagOverrides(_:)`). **Can:** turn on, on their own
device, a feature that hasn't been released, with any value of the flag's own kind. **Can't:**
override a flag the adapter doesn't list, change a flag the server enforces (an entitlement it
checks, content it serves only with the flag on), or clear an override the app set itself.
**Limits:** overrides clear as the session ends, and those a killed session left clear as the
next launch makes the capability; with `scope: .persistent` they stay until a sidecar clears them.

### Experiment overrides

``DebugDrawerExperimentOverrides`` (`.experimentOverrides(_:)`). **Can:** force a listed
experiment into one of its listed variants on their own device, so its events would pollute the
experiment's data. **Can't:** force an unlisted experiment or a variant it doesn't have.
**Limits:** the adapter's required `overriddenExperimentsDidChange(_:)` hook, and
`isExcludedFromAnalytics`, tell the app's analytics to leave the device out while any override
holds; overrides clear with the session, and after a kill at the next launch.

### Log levels

``DebugDrawerLogLevels`` (`.logLevels(_:)`). **Can:** raise a listed subsystem of the app's own
logger to a listed level, so the app logs more of what it handles, personal data among it, to
wherever its logger already writes. **Can't:** read a single line through this capability: it
captures none. **Limits:** keep the logger's own redaction on at verbose levels; levels reset with
the session, and after a kill at the next launch.

### Diagnostics capture

``DebugDrawerDiagnosticsCapture`` (`.diagnosticsCapture(_:)`). **Can:** start a capture of the
log lines and requests the app hands it, and read them, redacted, during the session. That is the
real data of whoever uses the device. **Can't:** capture anything the app doesn't hand over
(nothing is intercepted), or anything outside a session they started it in. **Limits:**
redaction before anything is kept, only JSON bodies, bounded size, and deletion as the session
ends or a gate turns off, and after a kill at the next launch. While it runs the capture sits in
the group's container, where every app of the group can read it.

### Bug reports

``DebugDrawerBugReports`` (`.bugReports(_:)`). **Can:** receive the reports taken during their
session: a screenshot of the app's key window (not redacted), the capture's recent lines and the
state the app chooses. **Can't:** take a report: only the app's own trigger does, in a session,
through the same gates as a command; the library adds no trigger. The app never uploads.
**Limits:** note and state redacted, bounded size, deletion as the session ends.

### Scenarios

``DebugDrawerScenarios`` (`.scenarios(_:launchURL:)`). **Can:** run any registered scenario's
handler with any value its declared parameters take, putting their own device in whatever state
those handlers reach. **Can't:** run an unregistered scenario, pass an undeclared parameter, or a
value out of its kind, range, length or options. **Limits:** what a handler did can't be undone;
register only scenarios fit for production, bound each parameter, and keep the server's own checks.

### Auth actions

``DebugDrawerAuthActions`` (`.authActions(_:launchURL:)`). **Can:** expire, refresh or end the
sign-in of the app on their own device. **Can't:** read a token: the handlers take nothing from
the sidecar and return only a status and a message written in the app's source. **Limits:** an
action of the app's own that reaches further (ending every session on the server) deserves
`requiringGrant()`.

### Environments

``DebugDrawerEnvironments`` (`.environments(default:allowing:_:adapter:)`). **Can:** point the
app's traffic, the signed-in account's credentials with it, at another backend the app
allowlists, such as your staging. **Can't:** name a backend the app didn't list, or send a URL:
environments travel by ID, and the adapter maps the ID to the app's own configuration.
**Limits:** the allowlist is required and written in source, the switch reverts with the session,
and after a kill at the next launch; configure a grant policy, or add `requiringGrant()`, and show
the backend in the session indicator.

### Allowlisted UserDefaults

``DebugDrawerUserDefaults`` (`.userDefaults(_:)`). **Can:** read and change any allowlisted key,
within its kind and bounds, and with it whatever the app derives from that value. **Can't:**
list the domain, or read or write any other key. **Limits:** every edit is audited with its old
and new value; edits revert with the session by default, and after a kill at the next launch.
Never allowlist a secret.

### Tweaks

`TweaksModel` (`.tweaks(_:)`, `DebugDrawerTweaks`). **Can:** set any tweak marked
`.productionSafe()` to one of its values, which the app reads now and after a relaunch. The risk
is whatever those tweaks control. **Can't:** read or change a tweak that isn't production-safe,
or set a value the tweak doesn't offer. **Limits:** persistent by default; with
`scope: .session(revertWith: .resetAll)` they reset as the session ends, and after a kill as the
next launch enables the capability.

### Analytics events

`AnalyticsEventsMirror` (`.analyticsEvents(sessions:redaction:capacity:)`,
`DebugDrawerAnalytics`). **Can:** read the events the app records during their session, redacted.
**Can't:** read events from before the session or after it, or unredacted values. **Limits:**
add redaction rules for your own event properties; under a grant policy the mirror serves only a
session whose grant lists it, and mirrors nothing to any other.

### Localization review and accessibility overrides

`LocalizationReview` and `AccessibilityEnvironmentOverrides` (`DebugDrawerLocalization`,
`DebugDrawerAccessibility`). **Can:** show string keys or pseudo-localized text, or another
Dynamic Type size, Increase Contrast or Reduce Motion, in the app on their own device. **Can't:**
change the device's settings or keep a mode past the session. **Limits:** session-scoped, always,
in memory only.

### Crash reports and MetricKit payloads

`MetricKitPayloadsMirror` (`.metricKitPayloads(sessions:)`, `DebugDrawerMetricKit`). **Can:** read
the MetricKit payloads the app kept (metrics, crashes, hangs, the system's stack frames) during a
session, and delete the app's copies. **Can't:** read an Objective-C exception's reason, which is
masked by default, or install any handler: the capability only subscribes to MetricKit.
**Limits:** kept in the app's own Application Support, not the group, and served only during a
session; under a grant policy it serves only a session whose grant lists it.

### Network mocking

`NetworkMocking` (`.networkMocking(_:)`, `DebugDrawerNetwork`). **Can:** answer the app's requests
to allowed hosts with responses of their own, slowed or failed, for their session, so the app
shows what the server never sent. **Can't:** reach a host the app didn't allow, a session the app
didn't configure with `NetworkMockingURLProtocol`, `URLSession.shared`, or the real responses;
regular expressions and file bodies are refused. **Limits:** always needs a grant listing it;
rules clear with the session; show `snapshot.isActive` in the session indicator.

### Location spoofing

`LocationSpoofing` (`.locationSpoofing(_:)`, `DebugDrawerLocation`). **Can:** make the app take a
coordinate of their choice for the device's location during their session, which is what
location fraud does (a region's offer, a check-in, a delivery zone). **Can't:** move a reading the
app doesn't pass through `location(replacing:)` or `locations(replacing:)`: nothing is
intercepted, so Core Location, MapKit and the system keep the real location; read the device's
location, which is never in the snapshot; or keep a spoof past the session, its expiry date or a
kill. **Limits:** the app is told as spoofing starts and ends (`spoofingDidChange`, required), so
its own fraud checks can flag what it read meanwhile; route only the readings a tester should
move, and keep fraud checks on Core Location's own; configure a grant policy, or add
`requiringGrant()`, and show the spoofed location in the session indicator.

### Push token

`PushRegistrationMirror` (`.pushRegistration(_:)`, `DebugDrawerNotifications`). **Can:** read the
device's APNs token, which APNs server it belongs to, and the app's notification settings, during
a session. **Can't:** send a push with it: that takes the company's APNs key, which neither app
holds. **Limits:** the token is a device identifier, so it is served only during a session (and
under a policy only to a grant that lists it), and nowhere but the snapshot file while one is open.

### App state reset

`AppStateResetRequests` (`.appStateReset(_:)`, `DebugDrawerAppStateReset`). **Can:** delete what
the allowed categories hold on their own device, after confirming the listing: defaults, files,
caches, cookies, the URL cache, and the keychain only when the app passes `allowingKeychain: true`.
Files and Caches also clear the containers of the app's groups, which other apps of the group
share. **Can't:** delete a category the app didn't allow, anything the confirmation didn't list,
or DebugDrawer's own state and the receiver's store. **Limits:** nothing is read until asked in a
session, values are never listed, and a reset runs only in the foreground; deleted data doesn't
come back, so consider `requiringGrant()`.

### Performance traces

`PerformanceTraces` (`.performanceTraces(_:)`, `DebugDrawerHangDetector`). **Can:** record the
main thread's hitches and hangs, with stack frames and image load addresses, and the intervals
the app marks, during their session. **Can't:** read user data through it: interval names are
literals in the app's source. **Limits:** nothing runs until the sidecar starts it in a session,
and the recording is deleted as the session ends.

### App state snapshot

`DebugDrawerAppState` (`.appState(_:)`, `DebugDrawerAppInfo`). **Can:** read the build, its
configuration, and only what the app registers: overrides, experiment buckets, the environment,
a hashed user ID and values of its own. **Can't:** read the raw user ID (it is hashed with a key
that never leaves the app), or anything not registered. **Limits:** served only during a session,
and under a policy only to a grant that lists it. Never register a secret.

### A model of the app's own

`.model(_:id:scope:)` serves any `DebugDrawerPluginModel`. Its risk is whatever its commands do;
its snapshot is readable during a session, as above. With a session scope its revert runs as the session ends,
and after a kill as the next launch enables it (the receiver's record, under "Sessions"), so its
revert command should do nothing when nothing is left to put back.

## Known limitations

- **What a session reads is readable by the group while it lasts.** See "What a sidecar can
  read, and when".
- **A grant can open one more session after a relaunch.** See "Signed grants".
- **The audit log is in memory.** Forward it, or it goes with the process.

## Distributing the sidecar

### The same team, always

The sidecar must be signed by the same developer team as the production app, as an app group
belongs to one team. Every working option below keeps that: the sidecar is an app of your team,
distributed only to your employees.

The kit builds its views in debug builds only; a release build of it gets stand-ins that list no
app. So archive the sidecar in the Debug configuration (or one that compiles DebugDrawer with
`DEBUG`), whichever way you distribute it.

### What works

- **TestFlight, internal testers.** Members of your App Store Connect team install it through
  TestFlight. Internal builds need no Beta App Review, and builds expire after 90 days, so plan
  to upload again.
- **A private app in Apple Business Manager.** A custom app distributed only to your own
  organization, installed through device management or redemption codes, signed by your team. It
  goes through App Review. Whether App Review accepts a Debug-configuration build of an internal
  tool isn't verified here.
- **Development or ad hoc signing**, for a small team: builds signed by your team for devices
  registered to it.
- **On the Mac: Developer ID, notarized**, signed by your team, with the team-ID-prefixed group in
  both apps' entitlements, distributed through your own channel (an internal download, device
  management). TestFlight internal testing and Apple Business Manager custom apps also exist for
  Mac apps; check Apple's current terms for your case.

### What doesn't

- **An Apple Developer Enterprise Program account.** It is a separate account with its own Team
  ID, and an app group can't span two teams, so an in-house sidecar can't share the production
  app's group: it finds no app.
- **A public TestFlight link.** Anyone who has the link can install it. Treat a sidecar shared that
  way as leaked. External testers by invitation are outside your team too, and their builds go
  through Beta App Review; keep the sidecar to internal testers.
- **The App Store, public or unlisted.** An unlisted app is still available to anyone with its
  link.

### If it leaks anyway

A leaked sidecar acts only on the device it is installed on, and only on what the production app
enabled. To shut it out: turn the receiver's gate off (or the risky capabilities' gates) in your
remote configuration, require grants from your server in the next release, and expire the
sidecar's TestFlight build or revoke its signing.

## App Review notes for the production app

The receiver is in the build you submit, so say what it is in the notes for the reviewer. Keep
it factual; this is not a statement of what App Review will decide. What is true of every
receiver:

- It has no UI and adds no feature a customer can reach. It does nothing until a companion app,
  signed by your team and sharing your app group, opens a session on the same device; that app
  is distributed to your employees only.
- It downloads no code and evaluates nothing it receives: each command is decoded into a fixed
  type and picks among what the app declared in its source.
- It makes no network connection and installs no interception: no method replacement, no
  `URLProtocol` registered for the app. Network mocking, if you enable it, answers only through a
  URL protocol the app lists in its own session configurations; location spoofing, only through
  the readings the app passes through it.
- Its background request, while a session is open, is a UIKit background task, or on iOS 26 and
  later a `BGContinuedProcessingTask` the person starts and the system shows. It claims no audio,
  location or VoIP mode.

Then add what your build enables: which capabilities, what each lets your employees change (a
flag's value, a backend among those you listed), and how you limit it (grants, the remote gate).
If you enable `DebugDrawerAccessibility`, its modifier sets SwiftUI's `_colorSchemeContrast` and
`_accessibilityReduceMotion` environment values, which are public in SwiftUI's interface but
undocumented; leave that module out if that matters to you.

## A checklist for the host

- Enable only the capabilities you need, each with the narrowest list: flags, keys, hosts,
  environments, categories.
- Make every capability at startup, before the app reads what it changes.
- Draw a session indicator, with what is switched or mocked.
- Back ``DebugDrawerReceiver/isAllowed`` with remote configuration, and call
  ``DebugDrawerReceiver/reevaluateGates()`` as it changes.
- Configure a ``DebugDrawerGrantPolicy`` with short grants if you enable a high-risk capability,
  or on the Mac.
- Forward ``DebugDrawerSessions/auditEntries``.
- Give each app its own group if their data must stay apart.
- Distribute the sidecar to your own team only.
