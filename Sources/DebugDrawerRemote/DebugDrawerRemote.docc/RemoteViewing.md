# Remote Viewing

Read a phone's logs and requests on a Mac: serve the Network and Console plugins' models, or any
plugin's, to a viewer on another device over the local network.

## Overview

`DebugDrawerRemote` serves plugin models to a viewer on another device, so a phone's traffic can
be read on a Mac's screen. Nothing listens or advertises until the app starts the server, and a
viewer reaches nothing until it pairs with a code the device shows.

### Serving from the device

On the device, in a debug build, register the models to offer and start the server:

```swift
import DebugDrawer
import DebugDrawerConsolePlugin
import DebugDrawerNetworkPlugin
import DebugDrawerRemote
import SwiftUI

@MainActor
final class RemoteViewing {
    let registry = DebugDrawerModelRegistry()
    let server: DebugDrawerNetworkServer

    init() {
        registry.register(NetworkModel.shared, id: NetworkPlugin().id)
        registry.register(ConsoleModel.shared, id: ConsolePlugin().id)
        server = DebugDrawerNetworkServer(registry: registry)
    }

    func enable() async throws {
        try await server.start()
    }
}
```

The server listens on a port the system picks and advertises itself over Bonjour under the
device's name. `DebugDrawerNetworkServerConfiguration` sets the name and the port. Its `.loopback`
configuration listens on 127.0.0.1 only and advertises nothing, for a viewer on the same Mac as a
simulator.

### Pairing

When a viewer connects, the server adds it to `pairingRequests` with a new six-digit code.
`RemoteViewingPlugin` shows these in the drawer, where the person holding the device sees them.
The plugin shows whether the server listens and on which port, with Start Serving and Stop
Serving; each viewer asking to pair, with its name, its code and a Reject button; and each paired
viewer, with a Disconnect button. Its badge counts the viewers waiting for their code:

```swift
@MainActor
func showRemoteViewing(_ remote: RemoteViewing) {
    DebugDrawer.shared.registerGlobal(RemoteViewingPlugin(server: remote.server))
}
```

With the plugin listed, the app doesn't need to call `enable()` at all. The person starts serving
from the drawer when they want a viewer in.

The person types the code into the viewer, which then stays paired for as long as its connection
lasts. A wrong code, or anything sent before pairing, closes the connection. Each code is good for
one try, and every try shows on the device. Pairing isn't stored anywhere, so a viewer pairs again
after either app relaunches. Traffic is not encrypted, so use it in debug builds, on a network you
trust.

### Versions

The device's app and the viewer can come from different releases. Once paired, each sends a hello
naming the protocol's major version it speaks, the oldest one it still speaks, and what it can do
(`commands`, `unsubscribe`, `acknowledgements`). Builds one major version apart connect and use
only what both have. Builds two apart don't connect: the device closes the connection, and the
viewer's `connect` throws
`DebugDrawerTransportError.incompatibleVersion`. A build drops a message of a kind it doesn't
know, logs it once per kind, and keeps the connection up. Before pairing, the device sends nothing
about itself, the hello included.

The same rules hold for a sidecar app over the socket and the app-group store. The store's files
also carry a schema version and the writer's version, and are migrated forward as they are read. A
sidecar holds a `DebugDrawerSidecarTransport`, which uses the socket while the app answers on it
and the store while it doesn't. It switches each way by itself, and no command is lost or
performed twice. The core DebugDrawer documentation's Writing Global and Local Plugins article
covers this under "Reaching a model from another process".

### A sidecar on the Mac

Both apps run at once on a Mac, so the socket is the usual channel and the store is the
fallback. Both apps find the group's container with `DebugDrawerAppGroupContainer`, sandboxed or
not. The app hands its `socketPath` and `storeDirectory` to its servers, and the sidecar hands
`socketPath(of:)` and `appDirectory(of:)`, naming the app by its bundle ID, to its transport. List
the group in each app's debug entitlements and sign both apps with the same team. Prefix the
group with the team ID (or list a `group.` one in a provisioning profile), so macOS
doesn't ask whether one app may access another's data:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>TEAMID.com.example.debug</string>
</array>
```

If the system refuses the container (the sandbox without the group, a declined prompt, the files'
modes), the server's `start()` or the transport's initializer throws
`DebugDrawerTransportError.accessDenied`, whose `localizedDescription` says what to fix, and
nothing is written anywhere. A group with no container throws `noAppGroupContainer`. A sidecar
refused only the socket publishes `socketError` and reads the store.

### Viewing on the Mac

In the viewer, `DebugDrawerNetworkBrowser` lists the devices that are advertising, and a
`DebugDrawerNetworkTransport` connects to one. It is a `DebugDrawerTransport`, so once paired it
hands out the same transports the plugins' views draw from:

```swift
@MainActor
func viewNetwork(of device: DebugDrawerNetworkDevice, code: String) async throws
    -> DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand> {
    let viewer = DebugDrawerNetworkTransport(endpoint: device.endpoint, viewerName: "Studio Mac")
    try await viewer.pair(code: code)
    return try await viewer.connect(toPlugin: NetworkPlugin().id, snapshot: NetworkSnapshot.self, command: NetworkCommand.self)
}
```

You can also show the device with the plugins' own views. `NetworkPluginView(transport:)` and
`ConsolePluginView(transport:)` take the paired transport, or any `DebugDrawerTransport` (a
sidecar's too). They show "Waiting for Network…" until the device's model answers, then draw what
the device's drawer draws, live, and send each filter, mock or clear back to the device. They
intercept and capture nothing on the Mac, and draw nothing in release builds:

```swift
struct DeviceView: View {
    let device: DebugDrawerNetworkTransport

    var body: some View {
        HStack(alignment: .top) {
            ScrollView { NetworkPluginView(transport: device) }
            ScrollView { ConsolePluginView(transport: device) }
        }
    }
}
```

A sidecar can relay a production app to such a viewer too, within the session it opens. The
Sidecar Kit documentation's Device Lab article describes it.

### In the example apps

The macOS example app has a viewer under Debug > Remote Viewer. Once you click Look for Devices it
lists the devices it finds, or it connects to an address (`127.0.0.1:<port>` for a server on
loopback). It then asks for the code and shows the device's Network and Console. The example apps
serve themselves through `RemoteViewingPlugin` in their drawer. Launch them with
`-ServeRemoteViewers` to start serving at launch, and add `-RemoteViewersOnLoopback` to listen on
127.0.0.1 alone.

### Info.plist and entitlements

iOS asks the person before an app uses the local network, and both the device's app and the viewer
must declare the service they advertise or browse for. Add to each:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Lets a Mac on your network show this debug build's logs and requests.</string>
<key>NSBonjourServices</key>
<array>
    <string>_debugdrawer._tcp</string>
</array>
```

Put them in the debug configuration's Info.plist only, as release builds never listen. A sandboxed
Mac app also needs the `com.apple.security.network.server` entitlement to serve, and
`com.apple.security.network.client` to view. `.loopback` needs nothing else, as no permission
covers it.

Release builds get stand-ins: the server never listens, the browser finds nothing, and a viewer's
pairing fails as unreachable.
