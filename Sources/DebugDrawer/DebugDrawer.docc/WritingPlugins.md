# Writing Global and Local Plugins

Write a tool of your own as a plugin, and register it for the app's lifetime or for as long as
one of its views is on screen.

## Overview

A plugin is a type that adopts ``DebugDrawerPlugin``: a ``DebugDrawerPlugin/title``, an
``DebugDrawerPlugin/icon`` (an SF Symbol's name) and a ``DebugDrawerPlugin/body``. Everything
else has a default. The drawer shows each plugin as a collapsible section with that title and
icon, and builds its body on the main actor, as SwiftUI builds a view's.

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
declares, each found by its title or keywords:

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
            }
        ]
    }
}
```

### Badges and toasts

A plugin can raise a problem while the drawer is closed. ``DebugDrawerPlugin/setBadge(_:)`` puts
a count on its header until ``DebugDrawerPlugin/clearBadge()``, and
``DebugDrawerPlugin/postToast(_:)`` shows a toast in the window's corner that opens the drawer at
the plugin when tapped. Posts from one plugin coalesce into one toast that counts them. These are
methods on the plugin, so they compile in release, where they do nothing.

```swift
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
is closed.

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

### A model apart from the view

A plugin whose data should be read, or driven, without its view (by a test, by another tool, or
from another process) splits into a model and a view. The model adopts
``DebugDrawerPluginModel``: it holds no SwiftUI types, takes its services through its initializer,
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
Browser, Loaded Libraries, Deep Link, Screenshot and Location plugins are built this way
(`NetworkModel`, `ConsoleModel`, `ViewInspectorModel`, `AccessibilityModel`, `LaunchTimeModel`,
`CookiesModel`, `FileBrowserModel`, `LoadedLibrariesModel`, `DeepLinkModel`, `ScreenshotModel`,
`LocationModel`). A plugin that acts on the app's live windows, as the View Inspector does, keeps its windows and views behind a service
the model takes at init and puts only values read from them in its snapshot.

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
| Local network (the `DebugDrawerRemote` library) | `DebugDrawerNetworkServer` | `DebugDrawerNetworkTransport` | A viewer on another device, such as a Mac showing a phone's logs; nothing listens until the app starts the server, and each viewer pairs with a code the device shows |

```swift
@MainActor
final class CounterSharing {
    let registry = DebugDrawerModelRegistry()
    let socketServer: DebugDrawerSocketServer
    let storeServer: DebugDrawerAppGroupStoreServer

    init(model: CounterModel, container: URL) throws {
        registry.register(model, id: "MyApp.CounterPlugin")
        socketServer = DebugDrawerSocketServer(registry: registry, socketPath: container.appending(path: "drawer.sock").path)
        storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: container.appending(path: "DebugDrawer"))
        try socketServer.start()
        try storeServer.start()
    }
}
```

The viewer picks a transport per connection, at run time, and can hold several at once, to one
model or to many: here, the socket while the app answers on it, and the store when it doesn't.

```swift
@MainActor
func counterTransport(container: URL) async throws -> DebugDrawerPluginTransport<CounterModel.Snapshot, CounterModel.Command> {
    let connection: any DebugDrawerTransport
    do {
        connection = try DebugDrawerSocketTransport(socketPath: container.appending(path: "drawer.sock").path)
    } catch {
        connection = try DebugDrawerAppGroupStoreTransport(directory: container.appending(path: "DebugDrawer"))
    }
    return try await connection.connect(toPlugin: "MyApp.CounterPlugin", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)
}
```

`connect` returns once the plugin's first snapshot is in, waiting while the app hasn't
registered the model yet; it throws ``DebugDrawerTransportError/mismatchedTypes`` when the model
under that ID has other types. A transport it returns holds its connection open. When the app
stops serving the socket, the transport keeps its last snapshot, drops later commands, and the
socket transport's ``DebugDrawerSocketTransport/isConnected`` turns `false`.

**Platforms.** Each transport builds wherever core does: macOS, iOS, Mac Catalyst, visionOS,
tvOS and watchOS. App groups and Unix domain sockets in the group's container work between two
apps of one team on iOS, macOS and visionOS, which is where a sidecar runs; tvOS and watchOS
build the same code for an app talking to its own extensions. A socket's path holds at most 103
bytes, which a group container's path leaves room for. Everything here is for debug builds:
release builds get stand-ins whose connections throw ``DebugDrawerTransportError/unreachable``
and whose servers serve nothing.

**The wire.** Whatever leaves the process is one message: a JSON object with the format's
`version` (1), its `kind` (`subscribe`, `snapshot` or `command`), the `pluginID`, and the
`payload`, the plugin's own snapshot or command encoded as JSON (keys sorted) and carried as
base64. A receiver drops a message of another version. On a byte stream, the socket's or a
network connection's, each message is a frame: a 4-byte big-endian length, then that many bytes
of JSON, at most 64 MiB. A viewer sends `subscribe` for each plugin it connects to and gets that
plugin's current snapshot, then one after each change, each different from the one before; it
sends `command`s back. The store keeps one message per file, written atomically:
`snapshots/<plugin ID>.json` holds each plugin's newest snapshot (the ID percent-encoded), and
`commands/<time>-<count>-<UUID>.json` holds each command until the app performs it, oldest
first, and removes it. Both sides learn of a change from a dispatch source on the directory, so
nothing polls.

**Why it is built this way.** The protocol hands out ``DebugDrawerPluginTransport``s rather than
raw messages, so a view never changes and the in-process transport keeps `direct(to:)`'s
synchronous commands; a protocol rather than a compile-time choice, so a viewer can hold two
transports at once and switch when the app goes to the background. Registration is explicit,
not done by plugins as they install, so an app offers only what it chooses. The socket is POSIX
`AF_UNIX` with dispatch sources rather than Network.framework, whose listener documents no
Unix-domain support; the network transport frames the same messages over Network.framework
instead, which it needs for Bonjour. The store is files and a directory's dispatch source
rather than `NSFilePresenter` (file coordination across processes would bind both apps to it for
every write) or a Darwin notification (a name to agree on and a second step to read what
changed). JSON rather than a binary property list, so a capture can be read and a viewer on any
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
    private let buffer = CaptureBuffer<AnalyticsEvent>(maxCount: 1_000, maxByteCount: 1_048_576) {
        $0.payload.count
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

The shipped plugins' test targets check the contract with shared checks: installing twice and in a
second drawer, uninstalling and installing again, the app's results with the plugin and without,
the capture's bound and the drawer's own work. Each runs in a child process of its own
(`#expect(processExitsWith:)`), since installing changes the whole process. A swizzle's check
compares the method implementations it reads before the install and after the uninstall.

