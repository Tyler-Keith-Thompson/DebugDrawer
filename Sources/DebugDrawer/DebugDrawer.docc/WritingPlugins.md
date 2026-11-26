# Writing Global and Local Plugins

Write a tool of your own as a plugin, and register it for the app's lifetime or for as long as
one of its views is on screen.

## Overview

A plugin is a type that adopts ``DebugDrawerPlugin``: a ``DebugDrawerPlugin/title``, an
``DebugDrawerPlugin/icon`` (an SF Symbol's name) and a ``DebugDrawerPlugin/body``. Everything
else has a default. The drawer shows each plugin as a collapsible section with that title and
icon, and builds its body on the main actor, as SwiftUI builds a view's.

The protocol is isolated to the main actor, so a plugin type is too: make and register it there.
A plugin that declares its own ``DebugDrawerPlugin/id`` as a computed property marks it
`nonisolated` (`nonisolated var id: String { "Orders" }`), since `Identifiable` reads it from any
thread.

The protocol exists in every build, so a plugin compiles in release too, as long as its body
uses only API that does (<doc:ReleaseBuilds>).

### Global plugins

A global plugin stays in the drawer until
``DebugDrawer/DebugDrawer/unregisterGlobal(id:)`` removes it, usually for the app's lifetime.
Register it once, at launch, with ``DebugDrawer/DebugDrawer/registerGlobal(_:)``:

```swift
DebugDrawer.shared.registerGlobal(CachePlugin())
```

Global plugins are listed by ``DebugDrawerPlugin/category``, a string a plugin may declare; one
that declares none is in `General`, listed last. The developer can pin a plugin to the top or
reorder it within its group from its header's context menu, and the drawer remembers that.

### Local plugins

A local plugin belongs to a screen: it is in the drawer while that screen's view is on screen,
listed above the global plugins. Attach it with `debugLocalPlugin(_:)`:

```swift
struct OrderPlugin: DebugDrawerPlugin {
    let orderID: String

    var title = "Order"
    var icon = "shippingbox"

    var body: some View {
        DebugDrawerKeyValueRow("Order ID", value: orderID)
    }
}

struct OrderDetailView: View {
    let orderID: String

    var body: some View {
        Text("Order \(orderID)")
            .debugLocalPlugin(OrderPlugin(orderID: orderID))
    }
}
```

The modifier registers the plugin when the view appears and removes it when the view disappears.
In an app with several windows (on iPadOS, scenes), the plugin is listed only in the drawer of the
window its view is in.
While the view is on screen, the drawer shows the plugin's latest value: when `orderID` changes,
the view hands the modifier a new `OrderPlugin`, and the plugin's section shows the new order.
When a new view registers a plugin with the same ID before the old one disappears, the old view's
disappearance leaves the new registration in place.

### Identity

``DebugDrawerPlugin/id`` defaults to the type's fully qualified name (`Orders.OrderPlugin` for an
`OrderPlugin` in the `Orders` module), which is what the drawer saves a plugin's collapsed state,
pin and order under, so plugins of one name in two modules are told apart. Declare an `id` of
your own only to register several instances of one type side by side. The drawer holds one global
plugin per ID: registering a plugin of another type under an ID already registered leaves the
first in place and logs an error naming both types.

The drawer keeps what it saves in a `UserDefaults` suite of its own, named after the app's bundle
identifier with `.debugdrawer` appended, so none of it shows among the app's standard defaults.

### Search actions

The drawer's search field finds plugins by title, and runs the ``DebugDrawerAction``s a plugin
declares, each found by its title or keywords. A plugin declares no actions unless it says so:

```swift
struct SessionPlugin: DebugDrawerPlugin {
    var title = "Session"
    var icon = "person.crop.circle"

    var body: some View {
        Text("Signed in")
    }

    var actions: [DebugDrawerAction] {
        [
            DebugDrawerAction("Expire token", keywords: ["auth", "logout"]) {
                UserDefaults.standard.removeObject(forKey: "authToken")
            },
        ]
    }
}
```

<doc:UsingTheDrawer> describes the search field and its keys.

### Badges and toasts

A plugin can raise a problem while the drawer is closed. ``DebugDrawerPlugin/setBadge(_:)`` puts
a count on its header until ``DebugDrawerPlugin/clearBadge()``, and
``DebugDrawerPlugin/postToast(_:)`` shows a toast in the window's corner that opens the drawer at
the plugin, expanded and scrolled into view, when tapped. Posts from one plugin coalesce into one
toast that shows the latest message and counts them, and a post made while the drawer is open is
dropped. The toast goes away by itself ``DebugDrawer/DebugDrawer/toastLifetime`` (6) seconds
after the last post, and stays while the pointer is over it or accessibility focus is on it.

Badges and toasts reach every drawer that holds the plugin, globally or locally:
``DebugDrawer/DebugDrawer/shared`` for a plugin installed there, a `DebugDrawer()` of your own for
one installed in it, and both for one in both. A plugin no drawer holds yet posts to
``DebugDrawer/DebugDrawer/shared``. The counts of Analytics, Crash Reports, Hangs, Leaks and
MetricKit badge only the drawers that installed the plugin: each drawer shows the count as it
installs the plugin and clears it as it removes it. These are methods on the plugin, so they
compile in release, where they do nothing.

```swift
struct UploadsPlugin: DebugDrawerPlugin {
    var title = "Uploads"
    var icon = "arrow.up.circle"

    var body: some View {
        Text("No uploads")
    }
}

let uploads = UploadsPlugin()
uploads.setBadge(2)
uploads.postToast("Upload of report.pdf failed")
uploads.clearBadge()
```

The person using the drawer can silence a plugin that posts too often: Silence Notices, in the
context menu of its section header, removes its badge and toast and drops the ones it posts from
then on, and a crossed-out bell on the header shows it is silenced; Allow Notices undoes it. The
choice is saved across launches. Code does the same with
``DebugDrawer/DebugDrawer/setNoticesMuted(_:forPlugin:)`` and reads it with
``DebugDrawer/DebugDrawer/isNoticesMuted(forPlugin:)``, both keyed by the plugin's
``DebugDrawerPlugin/id``. A plugin's own calls stay the same either way.

### A readout in the header or the HUD

A plugin can show something while its section is closed. Its
``DebugDrawerPlugin/headerAccessory`` sits at the trailing edge of its header row: a count of
what it found, a short summary, or a borderless action. Its ``DebugDrawerPlugin/hud`` is a
compact readout the developer can pin to the floating HUD, which stays on screen while the drawer
is closed (<doc:UsingTheDrawer> describes the HUD). A plugin declares no readout unless it says
so:

```swift
struct QueuePlugin: DebugDrawerPlugin {
    var title = "Queue"
    var icon = "tray.full"

    var body: some View {
        Text("3 jobs waiting")
    }

    var hud: Text? {
        Text("3 jobs")
    }
}
```

A plugin can declare both:

```swift
struct JobsPlugin: DebugDrawerPlugin {
    var title = "Jobs"
    var icon = "gearshape.2"
    var category = "Background"

    var body: some View {
        Text("2 jobs failed")
    }

    var headerAccessory: some View {
        DebugDrawerIssueCount(.error, count: 2)
    }

    var hud: Text? {
        Text("2 failed")
    }
}
```

### A plugin's state

A plugin is a value the drawer reads, not a view, so it holds no `@State`. Keep a plugin's
state in a view its body returns, or in an observable store the plugin and the app share, and
pass the services it uses (storage, a clock, the network) in through its initializer, so a test
can hand it fakes.

### Work that needs a clean view of the app

A plugin that needs the app without the drawer over it, as a screenshot does, runs its work in
`DebugDrawer.shared.performWhileHidden(drawer:_:)`. The call hides the HUD, and every open drawer
unless `drawer` is false, runs the work once that has drawn, then shows them again.

### Lifecycle

A plugin can start work as a drawer adds it, stop it as the drawer removes it, and do the costly
part only while its content is on screen. Each hook is optional, called on the main actor, and
does nothing by default, so a plugin that adopts none compiles unchanged:

- ``DebugDrawerPlugin/install(in:)``, once, as the drawer adds the plugin: when
  ``DebugDrawer/DebugDrawer/registerGlobal(_:)`` lists it, or when a local plugin's view first
  appears. Registering an ID already registered installs nothing again.
- ``DebugDrawerPlugin/didBecomeVisible(in:)``, as its content comes on screen: its section's body
  in an open drawer, the plugin shown alone, or its readout on the HUD. However many windows show
  it, the plugin hears it once.
- ``DebugDrawerPlugin/didBecomeHidden(in:)``, as the last of its content leaves the screen: the
  drawer closed, the section collapsed or the readout unpinned. A plugin removed while it is
  shown hears this first.
- ``DebugDrawerPlugin/uninstall(from:)``, once, as the drawer removes the plugin: through
  ``DebugDrawer/DebugDrawer/unregisterGlobal(id:)``, or as a local plugin's view disappears.

A plugin is a value, so the hooks start and stop something the plugin holds a reference to, such
as a monitor:

```swift
@MainActor
final class SocketMonitor {
    private(set) var isRunning = false
    var isSampling = false

    func start() { isRunning = true }
    func stop() { isRunning = false }
}

struct SocketPlugin: DebugDrawerPlugin {
    let monitor: SocketMonitor
    var title = "Sockets"
    var icon = "network"

    var body: some View {
        Text(monitor.isRunning ? "Watching sockets" : "Stopped")
    }

    func install(in drawer: DebugDrawer) { monitor.start() }
    func uninstall(from drawer: DebugDrawer) { monitor.stop() }
    func didBecomeVisible(in drawer: DebugDrawer) { monitor.isSampling = true }
    func didBecomeHidden(in drawer: DebugDrawer) { monitor.isSampling = false }
}
```

A local plugin's view hands the drawer a new value each time it updates; the hooks of the latest
value are the ones called, and a new value is not installed again.

### Drawers of your own

Each drawer owns the plugins registered with it and calls their hooks. ``DebugDrawer/DebugDrawer/shared``
is the app's: `debugDrawer()`, `attach(to:)` and the shipped plugins' `install*()` calls use it.
``DebugDrawer/DebugDrawer/init()`` makes another drawer with no plugins, which shares none of the
shared drawer's, so a test can register the plugin it checks with a drawer of its own and see its
hooks run; ``DebugDrawer/DebugDrawer/init(defaults:)`` also keeps what the drawer saves (pins,
order, the HUD) in a `UserDefaults` suite of its own.

```swift
let monitor = SocketMonitor()
let drawer = DebugDrawer()

drawer.registerGlobal(SocketPlugin(monitor: monitor)) // install(in:): the monitor starts
drawer.unregisterGlobal(id: SocketPlugin(monitor: monitor).id) // uninstall(from:): it stops
```

In release builds a drawer of your own is a stand-in too: it holds nothing and calls no hook.

Every shipped plugin starts its work in `install(in:)` and undoes it in `uninstall(from:)`, so
`unregisterGlobal(id:)` takes a plugin out of the app as well as out of the drawer. Network, Disk
I/O, Location and View Inspector give each method they swizzled its original implementation back
and unregister the URL protocol. Accessibility clears its overrides. The plugins that watch the
app stop their observers, handlers and threads and let go of what they captured. What a plugin
saved to disk or to `UserDefaults` (mock rules, earlier sessions, reports, settings) stays for the
next install, and installing again starts it all over. Work a plugin does for every app window is
counted by drawer, and stops once the last drawer holding the plugin removes it. If other code
swizzled a method again on top of the plugin's, putting the original back would break that code,
so the plugin leaves it in place and it calls straight through, recording nothing, until the
plugin is installed again.

When two drawers hold Network, Console or View Inspector, the one that installed it last gets
what it captures (requests, log lines, render counts), and Network's mock rules and conditions
come from that drawer's plugin. Once that drawer removes the plugin, the one before it captures
again. Location works the same way: `installLocation()` on a drawer of your own gives it a
simulator of its own, with its switch and coordinate kept in that drawer's defaults, and the app's
location managers get the locations of the drawer that installed it last.
`ScreenRecording.install(in:)` gives a drawer its own recorder, list and Show Touches setting. An
app that uses only the shared drawer sees no difference.

A shipped plugin made with its public initializer works over the shared stores, the ones
`install*()` fills. The Network, Console, View Inspector, Accessibility and Tweaks plugins also
take a model, or a store, of their own through an internal initializer, so their own tests can
build one over hand-written fakes and install it in a drawer of their own.

### A model apart from the view

A plugin whose data should be read, or driven, without its view (by a test, by another tool, or
from another process) splits into a model and a view. The model adopts
`DebugDrawerPluginModel`: it holds no SwiftUI types, takes its services through its initializer,
describes everything the view shows as a `Codable` snapshot, and changes only when it performs a
`Codable` command. Colors, fonts and formatting stay in the view.

```swift
@MainActor
final class CounterModel: DebugDrawerPluginModel {
    struct Snapshot: Codable, Equatable, Sendable {
        var count = 0
    }

    enum Command: Codable, Sendable {
        case increment
        case reset
    }

    @Published private(set) var snapshot = Snapshot()

    func perform(_ command: Command) {
        switch command {
        case .increment: snapshot.count += 1
        case .reset: snapshot.count = 0
        }
    }
}
```

The view takes a ``DebugDrawerPluginTransport`` rather than the model: it draws the transport's
``DebugDrawerPluginTransport/snapshot`` and hands what the user does to
``DebugDrawerPluginTransport/send(_:)``. The plugin's body joins the two in the process with
``DebugDrawerPluginTransport/direct(to:)``, through which the snapshot is the model's own and a
command is performed before `send` returns, so a control bound to the snapshot reads back the
value it just set:

```swift
struct CounterView: View {
    @StateObject private var transport: DebugDrawerPluginTransport<CounterModel.Snapshot, CounterModel.Command>

    init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<CounterModel.Snapshot, CounterModel.Command>) {
        _transport = StateObject(wrappedValue: transport())
    }

    var body: some View {
        DebugDrawerKeyValueRow("Count", value: "\(transport.snapshot.count)")
        Button("Add One") { transport.send(.increment) }
    }
}

struct CounterPlugin: DebugDrawerPlugin {
    let model: CounterModel
    var title = "Counter"
    var icon = "number.circle"

    var body: some View {
        CounterView(transport: .direct(to: model))
    }
}
```

Nothing else changes: the plugin registers as any other does, and its lifecycle hooks start and
stop the model's work as they would without one. The transport watches the model only while a view
holds it, so a hidden section costs nothing.
``DebugDrawerPluginTransport/snapshots()`` hands the same changes out as a stream of values, the
current snapshot first, for a connection to forward elsewhere; on the other side,
``DebugDrawerPluginTransport/init(initial:snapshots:send:)`` makes a transport from such a stream
and a closure that carries the commands back. A plugin that doesn't adopt the protocol keeps
working as it does. The Network, Console, View Inspector, Accessibility, Launch Time, Cookies, File
Browser, Loaded Libraries, Deep Link, Screenshot, Location, UserDefaults, Keychain, Disk I/O,
Performance, Energy and App Info plugins are built this way (`NetworkModel`, `ConsoleModel`,
`ViewInspectorModel`, `AccessibilityModel`, `LaunchTimeModel`, `CookiesModel`, `FileBrowserModel`,
`LoadedLibrariesModel`, `DeepLinkModel`, `ScreenshotModel`, `LocationModel`, `UserDefaultsModel`,
`KeychainModel`, `DiskIOModel`, `PerformanceModel`, `AppInfoModel`, and `EnergyMonitor`, the store
the app already starts and stops). A plugin that acts
on the app's live windows, as the View Inspector does, keeps its windows and views behind a service
the model takes at init and puts only values read from them in its snapshot. A model that reads
secrets, as Keychain reads passwords, keeps them out of its snapshot: the snapshot says a value
was read, and the plugin's own view asks the model for it in the process, so no transport can
carry it out of the app.

### Reaching a model from another process

A model can be read and driven from outside the drawer too: by another app of yours that shares
an app group with this one (a sidecar), or by a viewer on another machine. The app offers its
models in a ``DebugDrawerModelRegistry``, each under its plugin's ID, and serves the registry
over the transports a viewer may use. A viewer holds any ``DebugDrawerTransport`` and asks it
for a plugin; what comes back is the same ``DebugDrawerPluginTransport`` the plugin's view
already draws from, so neither the model nor the view knows which transport it is on.

| Transport | App's side | Viewer's side | When |
|---|---|---|---|
| In the process | (the registry itself) | ``DebugDrawerInProcessTransport`` | The drawer, or a test, in the app's own process; a command lands before `send` returns |
| Unix domain socket | ``DebugDrawerSocketServer`` | ``DebugDrawerSocketTransport`` | Both apps run; snapshots arrive as they change, commands land at once |
| App-group store | ``DebugDrawerAppGroupStoreServer`` | ``DebugDrawerAppGroupStoreTransport`` | Either app may be suspended; the viewer reads the last snapshots, and commands wait for the app |
| Socket, else store | Both servers above | ``DebugDrawerSidecarTransport`` | A sidecar app: the socket while the app answers on it, the store while it doesn't, switching on its own |
| Local network (the `DebugDrawerRemote` library) | `DebugDrawerNetworkServer` | `DebugDrawerNetworkTransport` | A viewer on another device, such as a Mac showing a phone's logs; nothing listens until the app starts the server, and each viewer pairs with a code the device shows |

```swift
@MainActor
final class CounterSharing {
    let registry = DebugDrawerModelRegistry()
    let socketServer: DebugDrawerSocketServer
    let storeServer: DebugDrawerAppGroupStoreServer

    init(model: CounterModel, group: DebugDrawerAppGroupContainer) throws {
        registry.register(model, id: "MyApp.CounterPlugin")
        socketServer = DebugDrawerSocketServer(registry: registry, socketPath: group.socketPath)
        storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: group.storeDirectory)
        try socketServer.start()
        try storeServer.start()
    }
}
```

The viewer picks a transport per connection, at run time, and can hold several at once, to one
model or to many. A sidecar holds a ``DebugDrawerSidecarTransport``: it reads the app over the
socket while the app answers on it and through the store while it doesn't, and switches each way
on its own, so the transport it hands out keeps drawing as the app goes to the background, quits
or comes back. Several apps can serve one group's store, each in its own directory, so the
sidecar names the app it reaches by its bundle ID:

```swift
@MainActor
func counterTransport(group: DebugDrawerAppGroupContainer, app bundleIdentifier: String) async throws
    -> DebugDrawerPluginTransport<CounterModel.Snapshot, CounterModel.Command> {
    let sidecar = try DebugDrawerSidecarTransport(
        socketPath: group.socketPath(of: bundleIdentifier), storeDirectory: group.appDirectory(of: bundleIdentifier)
    )
    return try await sidecar.connect(toPlugin: "MyApp.CounterPlugin", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)
}
```

`connect` returns once the plugin's first snapshot is in, waiting while the app hasn't
registered the model yet; it throws ``DebugDrawerTransportError/mismatchedTypes`` when the model
under that ID has other types. A transport it returns holds its connection open. When the app
stops serving the socket, a socket transport's plugin transports keep their last snapshot and drop
later commands, and ``DebugDrawerSocketTransport/isConnected`` turns `false`. The sidecar transport
reads the store instead (its ``DebugDrawerSidecarTransport/channel`` turns
``DebugDrawerSidecarTransport/Channel/store``), and goes back to the socket once the app makes it
again, which it learns from a dispatch source on the socket's directory. No command is lost or
performed twice across either switch: a command sent over the socket is kept until the app
acknowledges it, and those not acknowledged when the socket goes are left in the store, oldest
first; the app performs a command whose ID it has already performed no more. When the socket comes
back, each command still waiting in the store that the sidecar can take back (its file is still
there) goes over the socket first, so the commands land in the order sent. This needs both builds
to list the `acknowledgements` capability; with an app that doesn't, commands in flight when its
socket goes may be lost.

**Platforms.** Each transport builds wherever core does: macOS, iOS, Mac Catalyst, visionOS,
tvOS and watchOS. App groups and Unix domain sockets in the group's container work between two
apps of one team on iOS, macOS and visionOS, which is where a sidecar runs; tvOS and watchOS
build the same code for an app talking to its own extensions. A socket's address holds at most
103 bytes of path, and a group container's path can be longer (in the iOS simulator it is about
170 bytes before the socket's name): a longer path is reached by its file name, relative to its
directory, so only the file name must fit. Everything here is for debug builds:
release builds get stand-ins whose connections throw ``DebugDrawerTransportError/unreachable``
and whose servers serve nothing.

**The group's container.** Both sides resolve it with ``DebugDrawerAppGroupContainer``, which
calls `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`. The group's store is
`DebugDrawer/` there (``DebugDrawerAppGroupContainer/storeDirectory``, which the app's
``DebugDrawerAppGroupStoreServer`` takes), and each app that serves it keeps to a directory of its
own in it, named by its main bundle's identifier: `DebugDrawer/apps/<bundle ID>/`, with its
presence file, its socket (``DebugDrawerAppGroupContainer/socketPath``), its snapshots and the
commands for it. A sidecar reads one app's with ``DebugDrawerAppGroupContainer/appDirectory(of:)``
and ``DebugDrawerAppGroupContainer/socketPath(of:)``:

```swift
let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug")
```

**Several apps in one group.** Because each app serves only its own directory, a company's apps
can share one group and one sidecar: neither performs the other's commands, and neither serves
where the other's sidecar reads. That is as far as the library can keep them apart. The system
lets every app of a group read the whole container, so an app that must not see another's data
(another app's captured logs or requests) needs a group of its own: give each app its own group,
and have the sidecar join every one (`DebugDrawerSidecarView(groupIdentifiers:)` in
`DebugDrawerSidecarKit`).

It throws ``DebugDrawerTransportError/noAppGroupContainer`` where the system gives the group no
container (on iOS, visionOS, tvOS and watchOS, when the app's entitlements lack it), rather than
the transports falling back to a directory the group doesn't protect.

**On the Mac.** Both apps run at once there, so the socket is the norm and the store the
fallback, read while the app isn't running. `containerURL` gives `~/Library/Group
Containers/<group>` to a sandboxed app and to one outside the sandbox alike, so a host app that
isn't sandboxed and a sandboxed sidecar find the same directory; outside the sandbox only the
files' modes guard it, as they guard the rest of the user's home, which is one more reason the
servers run in debug builds only. Grant the group so macOS doesn't have to ask:

- List the group in `com.apple.security.application-groups` in both apps' entitlements, in the
  debug configuration.
- Sign both apps with the same team, and name the group with that team's ID as its prefix
  (`TEAMID.com.example.debug`), or with `group.` and a provisioning profile that lists it.

Without that (a group the signature doesn't vouch for, an ad hoc signature, another team's app),
macOS asks the person, the first time an app reaches the container, whether it may access data
from other apps, and the call that reached it waits for the answer.

**When access is refused.** When the sandbox, a declined prompt or the files' modes refuse the
container (EACCES or EPERM), the call that first reached it throws
``DebugDrawerTransportError/accessDenied``: ``DebugDrawerSocketServer/start()``,
``DebugDrawerAppGroupStoreServer/start()``, ``DebugDrawerSocketTransport/init(socketPath:)``,
``DebugDrawerAppGroupStoreTransport/init(directory:)`` and
``DebugDrawerSidecarTransport/init(socketPath:storeDirectory:)``. Each checks that it may read,
write and search its directories before it writes, so a directory it can't write fails there,
not in every later write. Nothing is written then, in the container or anywhere else. A sidecar
that reaches the store but is refused the socket (a socket another user made, say) publishes
``DebugDrawerSidecarTransport/socketError`` as `accessDenied`, reads the store meanwhile, and
tries the socket again each time it is made. Each error's `localizedDescription` says what to
fix, and the refused path is logged under the `DebugDrawer` subsystem's `DirectoryAccess`
category. A person who declined the prompt is asked again after
`tccutil reset SystemPolicyAppData <bundle ID>`.

**The wire.** Whatever leaves the process is one message: a JSON object with the envelope's
format `version` (1), its `kind` (`hello`, `subscribe`, `unsubscribe`, `snapshot`, `command` or
`acknowledgement`), the `pluginID`, and the `payload`, the plugin's own snapshot or command encoded
as JSON (keys sorted) and carried as base64; a command, and its acknowledgement, also carry its
`commandID`, a UUID. A receiver drops a message in another envelope format, and drops a
kind it doesn't know, logging that kind the first time a connection sends it, then reads on. On a
byte stream, the socket's or a network connection's, each message is a frame: a 4-byte
big-endian length, then that many bytes of JSON, at most 64 MiB. Each side of a stream sends a
`hello` first (below). A viewer sends `subscribe` for each plugin it connects to and gets that
plugin's current snapshot, then one after each change, each different from the one before; it
sends `command`s back, and `unsubscribe` once the last transport to a plugin is released. The
app sends an `acknowledgement` naming each command once it has performed it (or dropped it, with
no model to take it). The
store keeps one document per file: `snapshots/<plugin ID>.json` holds each plugin's newest
snapshot (the ID percent-encoded), and `commands/<time>-<count>-<UUID>.json` holds each command
until the app performs it, oldest first, and removes it. Both sides learn of a change from a
dispatch source on the directory, so nothing polls; the app also performs what waits as it starts
serving and as it comes back to the foreground, since a suspended app may hear nothing. Each
document is written to `<file>.<UUID>.partial` beside its file, then renamed over it, so a
process killed mid-write leaves the last complete document and a partial file no reader reads.
The store is bounded: one snapshot file per plugin (the app's server removes partial files there
as it starts), and at most 256 command files and 16 MiB, partial ones included, as a viewer
removes the oldest past either after leaving a command and leaves none larger.

**Versions.** The app and a viewer, a sidecar especially, ship on different schedules, so a
pairing of any two builds either works or fails clearly. On a stream, each side's `hello` names
the protocol's major version it speaks (2), the oldest it still speaks (1), and its capabilities:
`commands` (the viewer sends commands and the app performs them) and `unsubscribe` (the app stops
sending a plugin's snapshots when the viewer releases it), and `acknowledgements` (the app
acknowledges each command it performs, and performs a command ID once). Both sides agree on the
lower of the
two versions when each still speaks it, and use only the capabilities both list, so builds one
major version apart connect and use what they share. Two major versions apart they don't: the
app closes the connection and the viewer's connects throw
``DebugDrawerTransportError/incompatibleVersion``. A side that never says hello is taken to speak
version 1, which had no hello and took commands. Each store document carries the store's
`schemaVersion` (2) and the `writer`'s hello beside the message's keys: a reader skips a document
whose writer it shares no version with, migrates an older schema forward as it reads it (schema
1, a bare message, was written by version 1), and reads a newer one for the keys it knows. A
reader of bare messages still reads every document, as the message's keys are where they were.

**Sessions.** A registry made with ``DebugDrawerModelRegistry/init(sessions:)`` performs a
command a transport carries in only within a session a sidecar opened, and only on a model
registered with ``DebugDrawerModelRegistry/register(_:id:scope:)``; anything else is refused and
changes nothing. The gate is the same over the socket and the store. A refused command is still
acknowledged, and its ID remembered, so a ``DebugDrawerSidecarTransport`` doesn't send it again
on a switch: a refusal is final, and a sidecar sends the command anew once a session is open. `DebugDrawerSessions` is itself a model, served under
`DebugDrawerSessions.pluginID`: a sidecar connects to it as to any plugin, sends
`DebugDrawerSessionCommand.open(duration:grant:)` and `DebugDrawerSessionCommand.end` as commands,
and reads `DebugDrawerSessionState` snapshots, so sessions need no message kind or capability
of their own and work over every transport. A session expires at most
`DebugDrawerSessions.maximumDuration` after it opens; as it ends or expires, each capability
registered as `DebugDrawerChangeScope.session(revertWith:)` that a command changed performs its
reverting command once, and `DebugDrawerChangeScope.persistent` ones keep their changes. The
host reads `DebugDrawerSessions.snapshot` to draw its own indicator for as long as a session is
open, ends one with `DebugDrawerSessions.end()`, and reads `DebugDrawerSessions.auditLog`
(the newest `DebugDrawerSessions.auditCapacity` entries) or forwards every
`DebugDrawerAuditEntry` from `DebugDrawerSessions.auditEntries`. An entry holds its date,
session, capability and event, never what a command carried. Commands from the in-process
transport, the app's own drawer, aren't gated. The Sidecar Kit documentation's Sidecar Sessions article
shows the setup.

**Production builds.** Everything above is debug-only. A release build links the
`DebugDrawerReceiver` product instead: `DebugDrawerReceiver(directory:sessions:)` serves the same
store files, read by the same sidecar transports, but only for the capabilities the host passes to
`enable(_:)`, and refuses, logs and audits every other command, every command while none is
enabled, and every command outside a session. Before all of that, grants included, it asks the host's gates, so a
company can turn it off without a release: while `DebugDrawerReceiver.isAllowed` returns `false`
every command is refused as `receiverDisabled`, the open session ends as `disabledByHost` and no
capability's snapshot is served, and a capability enabled with `enable(_:isAllowed:)` whose gate
returns `false` is refused as `capabilityDisabled` and has its session-scoped change reverted at
once; the host calls `DebugDrawerReceiver.reevaluateGates()` as its configuration changes. A
plugin's capability needs nothing for this: the gates sit in the receiver. A capability is a model:
`.featureFlagOverrides(adapter)` over the host's `DebugDrawerFeatureFlagAdapter`, or
`.model(_:id:scope:)` for any plugin model, each with its `DebugDrawerChangeScope`. So a plugin
whose model should be drivable in production needs nothing more than its model: the host enables
it in the receiver, and in a debug build can show the same model in its drawer through
``DebugDrawerPluginTransport/direct(to:)``. A shipped plugin whose data a release build must hold
splits its UI-free half into a module of its own that depends on the receiver alone and that the
plugin re-exports, with its capability there: `DebugDrawerTweaks` holds the tweaks and
`.tweaks(...)`, which offers a sidecar only those marked production-safe and refuses a command
naming any other as `notExposed`, and `DebugDrawerAnalytics` holds the analytics sink and
`.analyticsEvents(sessions:redaction:capacity:)`, which mirrors only the events recorded during the
open session, redacted in the app before anything is kept. A capability that would otherwise
intercept, as the Localization plugin's live modes replace `Bundle`'s lookup, has the host opt
in instead: `DebugDrawerLocalization` holds `LocalizationReview`, which the host reads strings
through, and `.localizationReview()`, which shows their keys or pseudo text for the session, and
`DebugDrawerLocation` holds `LocationSpoofing`, which the host passes its location readings
through where the Location plugin exchanges `CLLocationManager`'s methods, and
`.locationSpoofing(_:)`, which replaces them for the session and tells the host as it does. One
whose effect is in SwiftUI's environment keeps the modifier that applies it in its module, where
it draws nothing: `DebugDrawerAccessibility` holds `.accessibilityEnvironmentOverrides()` for
the receiver and the same-named modifier for the host's root view. Both are session-scoped, with
no scope to choose. A model that follows the sessions this
way keeps nothing from before a session or after it, and redacts on the way in, since its snapshot
is written to the store as it is. Data that arrives before any session can, such as a crash's
MetricKit diagnostic on a later launch, is kept in the app's own storage instead and put in the
snapshot only while a session is open: `DebugDrawerMetricKit` holds the MetricKit subscriber and
`.metricKitPayloads(sessions:directory:redaction:capacity:)`, which captures through MetricKit
alone, never a crash handler, so nothing intercepts in the build that ships. A capability that
changes how the app talks to its servers takes the same care: `DebugDrawerNetwork` holds
`.networkMocking(_:)`, whose rules answer only the `URLSession`s the host lists
`NetworkMockingURLProtocol` in, only for the hosts it allows, only within a session whose grant
lists it, and registers nothing with URL loading and replaces no method. A capability that shows a
device identifier serves it only for the session: `DebugDrawerNotifications` holds
`.pushRegistration(_:)`, whose `PushRegistrationMirror` keeps the APNs device token the host hands
it in memory and puts it, with the push environment and the notification settings, in the snapshot
only while a session is open, and not for a session whose grant doesn't list it. The receiver's module holds
`DebugDrawerPluginModel`, the sessions and the store's wire format, real in every build, and
`DebugDrawer` re-exports it; it serves no socket and holds no view. The DebugDrawerReceiver
documentation's Serving a Sidecar from a Production Build article shows the setup.

**Grants.** Sessions made with a `DebugDrawerGrantPolicy`
(`DebugDrawerSessions(maximumDuration:auditCapacity:grantPolicy:)`) open only with a signed grant
the sidecar sends in `DebugDrawerSessionCommand.open(duration:grant:)`: the policy's verifier
authenticates it (`DebugDrawerSignedGrantVerifier` reads a JSON Web Token signed with Ed25519 or
P-256; a host conforms to `DebugDrawerGrantVerifier` for another format), then the sessions check
its audience, its `notBefore` (less the clock-skew tolerance) and expiry, and that no session
opened with it before. The session lasts no longer than the grant, and applies a command only to a
capability the grant lists (`DebugDrawerAuditEntry.Refusal.capabilityNotGranted` otherwise). This
holds for the debug registry's sessions as for the receiver's. A capability too risky to offer on
team signing alone declares it with `DebugDrawerReceiverCapability.requiringGrant()`: in a session
without a grant, which is every session without a policy, its commands are refused as
`DebugDrawerAuditEntry.Refusal.grantMissing`. Without a policy, nothing changes. The DebugDrawerReceiver
documentation's Signed Grants article documents the format and a test signer.

**In the background.** A `DebugDrawerBackgroundKeeper` made with the sessions keeps the app
running while one is open, so a sidecar in the foreground keeps the socket, and ends every request
as the session ends or expires; `DebugDrawerBackgroundKeeper.request` says what it holds. It
asks only for what the platform sanctions, and claims no background mode:

| Platform | Request | Limits |
|---|---|---|
| iOS, iPadOS 26 and later | `DebugDrawerBackgroundRequest.continuedProcessing` from `DebugDrawerBackgroundKeeper.startSession(duration:title:subtitle:)`, else `DebugDrawerBackgroundRequest.backgroundTask` | Started from a person's action in the foreground, with `<prefix>.*` in `BGTaskSchedulerPermittedIdentifiers`; runs at once or falls back; the system shows its progress and may end it, which ends the session. The Simulator refuses it. |
| iOS, iPadOS before 26; tvOS; visionOS | `DebugDrawerBackgroundRequest.backgroundTask` | About 30 seconds in the background, no system indicator; asked for again as the app returns to the foreground. |
| macOS, Mac Catalyst | `DebugDrawerBackgroundRequest.activity` | Keeps App Nap away; never expires; idle sleep allowed. |
| watchOS | `DebugDrawerBackgroundRequest.none` | `WKExtendedRuntimeSession` serves only its own session types, none of them a debug session. |

Made with the ``DebugDrawerSocketServer``, the keeper also ends the session when the last viewer
disconnects from the socket on its own (``DebugDrawerSocketServer/viewerDisconnections``), not
when the app stops the server. The keeper is part of `DebugDrawerReceiver` and works in release builds too. The DebugDrawerReceiver
documentation's Keeping the App Reachable in the Background article has the setup.

**Why it is built this way.** The protocol hands out ``DebugDrawerPluginTransport``s rather than
raw messages, so a view never changes and the in-process transport keeps `direct(to:)`'s
synchronous commands; a protocol rather than a compile-time choice, so a viewer can hold two
transports at once and switch when the app goes to the background. Registration is explicit,
not done by plugins as they install, so an app offers only what it chooses. The socket is POSIX
`AF_UNIX` with dispatch sources rather than Network.framework, whose listener documents no
Unix-domain support; a path too long for its address is bound and connected by its file name from
its directory, as no public call takes a directory beside the address (`bindat` and `connectat`
are in no SDK header). The sidecar transport acknowledges commands rather than sending each both
ways, so the store holds only what the socket couldn't carry; the network transport frames the same messages over Network.framework
instead, which it needs for Bonjour. The store is files and a directory's dispatch source
rather than `NSFilePresenter` (file coordination across processes would bind both apps to it for
every write) or a Darwin notification (a name to agree on and a second step to read what
changed). A snapshot replaces the plugin's last one rather than being appended to a ring file, as
a viewer wants the newest state, which the plugin already bounds. JSON rather than a binary
property list, so a capture can be read and a viewer on any
platform can write it.

### Capturing what the app does

A plugin that records events as the app makes them (log lines, requests, file calls) keeps them
in a ``CaptureBuffer``, as the Console, Network and Disk I/O plugins do, rather than an array of
its own. The buffer keeps the newest elements within a count and a byte total, evicting the
oldest, so a long session costs bounded memory, and it counts what it evicted, so the plugin can
say how many older entries were dropped. Appending is safe from any thread, so a hook that runs
on the app's threads appends at once and returns.

```swift
@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [AnalyticsEvent] = []
    @Published private(set) var droppedCount = 0
    private let buffer: CaptureBuffer<AnalyticsEvent>

    init(maxCount: Int = 1_000, maxByteCount: Int = 1_048_576) throws(CaptureBuffer<AnalyticsEvent>.InvalidLimit) {
        buffer = try CaptureBuffer(maxCount: maxCount, maxByteCount: maxByteCount) { $0.payload.count }
    }

    /// Called from any thread.
    nonisolated func record(_ event: AnalyticsEvent) {
        buffer.append(event)
        Task { @MainActor in self.refresh() }
    }

    func refresh() {
        let snapshot = buffer.snapshot()
        events = snapshot.elements
        droppedCount = snapshot.evictedCount
    }
}
```

Each element gets a stable ``CaptureBuffer/ElementID`` when it is appended, so a plugin can change it in
place later with ``CaptureBuffer/update(_:_:)`` (a request's response arriving) and the buffer
counts its new size against the byte bound. ``CaptureBuffer/generation`` grows with every
change, so a view compares it to skip work when nothing changed. A ``CaptureBuffer/Snapshot`` is a
value, `Codable` when the elements are, for a bug report or an export. In release builds the
buffer keeps nothing.

### Intercepting the app's calls

A plugin that changes how the app's own calls run (it swizzles a method, registers a URL protocol,
installs a hook or a monitor) keeps a contract, so the app behaves the same with it as without and
the developer can trust what it shows. The Network, Disk I/O, Location and View Inspector plugins
keep it, and a plugin of your own that intercepts should too:

- **Idempotent install.** Installing twice is installing once. ``DebugDrawerPlugin/install(in:)``
  runs once per drawer that adds the plugin, so the plugin counts the drawers holding it and
  intercepts on the first; replacing a method that already runs the plugin's code does nothing,
  so no call is intercepted, or recorded, twice.
- **Reversible.** ``DebugDrawerPlugin/uninstall(from:)``, from the last drawer holding the
  plugin, puts back exactly what the install changed: each replaced method gets the implementation
  it had (set back, not swapped a second time), a registered class is unregistered, a hook or
  monitor is removed, a switch is turned off. A second uninstall changes nothing, and installing
  again intercepts again. A method other code has replaced again since stays, and the plugin's
  code under it calls straight through while uninstalled.
- **No change in what the app sees.** With the plugin installed, a call returns, throws and writes
  what it would without it, beyond what the plugin is for and only while the developer turns that
  on: a mock rule's response, a simulated location, slowed animations. The plugin observes and
  passes the call on unchanged.
- **Bounded capture.** Whatever the plugin keeps of the app's calls has a cap: a
  ``CaptureBuffer`` with a count and a byte bound, a dictionary that evicts its oldest key, weak
  references to the app's objects. A long session costs bounded memory however busy the app is.
- **The drawer's own activity is filtered out.** What the drawer and its plugins do themselves
  (saving their settings, writing a bug report, a request a plugin sends on the app's behalf,
  drawing the drawer) never shows among the app's calls. File work runs with
  ``DebugDrawerActivity/isDrawerWork`` bound to `true`; a request a plugin sends itself carries
  a mark its interception skips; the drawer's views are never tracked.

Interception starts in ``DebugDrawerPlugin/install(in:)``, not when the app's `install*()` call
runs or when the module loads, so nothing is intercepted, or kept, before a drawer adds the plugin.

What the plugin captures goes to the store of the drawer that installed it last. The app's calls
carry no drawer, so a plugin can't tell which drawer one belongs to; it keeps the drawers holding
it in the order they installed it, and its interception reads the latest one's store. When that
drawer removes the plugin, the one before it captures again, and a store no drawer holds any more
forgets what it kept. A test that installs the plugin in a drawer of its own, over a store of its
own, sees the app's calls there while the app's drawer still holds the plugin, and nothing reaches
the shared store until it removes it. Network, Console, View Inspector and Location bind this way:
Location's swizzled `CLLocationManager` methods ask the simulator of the latest drawer, which takes
over the managers the one before was updating, and hands them back as it removes the plugin.

The shipped plugins' test targets check the contract with shared checks: installing twice and in a
second drawer, uninstalling and installing again, the app's results with the plugin and without,
the capture's bound and the drawer's own work. Each runs in a child process of its own
(`#expect(processExitsWith:)`), since installing changes the whole process. A swizzle's check
compares the method implementations it reads before the install and after the uninstall.

