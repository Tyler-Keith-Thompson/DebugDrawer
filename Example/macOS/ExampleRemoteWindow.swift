import AppKit
import DebugDrawer
import DebugDrawerConsolePlugin
import DebugDrawerNetworkPlugin
import DebugDrawerRemote
import DebugDrawerSidecarKit
import Network
import SwiftUI

// The Mac viewer of remote viewing: the devices advertising on the local network, a connection by
// address for a server on loopback (a simulator's, or this app's own with -RemoteViewersOnLoopback),
// the code the device shows, then that device's Network and Console, live. The example apps' device
// side is ExampleRemoteServer (the drawer's Remote Viewing plugin). A device's sidecar can relay a
// production app the same way (DD-107, the device-lab bridge: Example/Sidecar's Mac Viewer): then
// the window reads the relay's own snapshot and shows each capability the session shares with the
// sidecar kit's own plugin views, live, sending what the person changes back through the sidecar,
// until the session ends. Release builds compile it all, and there the browser finds nothing and
// pairing fails as unreachable.

/// Debug > Remote Viewer: the window, made the first time it is asked for.
@MainActor
final class ExampleRemoteWindow: NSObject {
    /// Launched with this argument, the app opens the window at launch.
    static let launchArgument = "-OpenRemoteViewer"
    private var window: NSWindow?

    /// Opens the window when the app was launched with ``launchArgument``.
    func openIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains(Self.launchArgument) else { return }
        show()
    }

    /// Brings the window in front, making it first.
    @objc func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Remote"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: ExampleRemoteViewer())
            window.setFrameAutosaveName("DebugDrawerExampleRemote")
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

/// What the window shows: the devices to pick from, the code prompt for one, or its plugins.
struct ExampleRemoteViewer: View {
    enum Screen {
        case devices
        case pairing(DebugDrawerNetworkTransport, deviceName: String)
        case paired(DebugDrawerNetworkTransport, deviceName: String)
    }

    @State private var screen = Screen.devices

    var body: some View {
        switch screen {
        case .devices:
            ExampleRemoteDeviceList { endpoint, name in
                let viewerName = Host.current().localizedName ?? "Mac"
                screen = .pairing(DebugDrawerNetworkTransport(endpoint: endpoint, viewerName: viewerName), deviceName: name)
            }
        case let .pairing(transport, name):
            ExampleRemotePairing(transport: transport, deviceName: name) {
                screen = .paired(transport, deviceName: name)
            } cancel: {
                transport.close()
                screen = .devices
            }
        case let .paired(transport, name):
            ExampleRemotePluginsView(transport: transport, deviceName: name) {
                transport.close()
                screen = .devices
            }
        }
    }
}

/// The devices the browser finds once asked to look, and an address to connect to instead.
struct ExampleRemoteDeviceList: View {
    let connect: (NWEndpoint, String) -> Void
    @StateObject private var browser = DebugDrawerNetworkBrowser()
    @State private var address = ""

    var body: some View {
        Form {
            Section("Devices on the Network") {
                // Browsing waits for the person: it is what asks macOS for the local network.
                HStack {
                    Text(browser.isBrowsing ? "Looking for devices serving remote viewers…" : "Not looking")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if browser.isBrowsing {
                        Button("Stop Looking") { browser.stop() }
                    } else {
                        Button("Look for Devices") { browser.start() }
                    }
                }
                ForEach(browser.devices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text([device.appName, device.platform].compactMap(\.self).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") { connect(device.endpoint, device.name) }
                            .accessibilityLabel("Connect to \(device.name)")
                    }
                }
            }
            Section("By Address") {
                HStack {
                    TextField("Host and Port", text: $address, prompt: Text("127.0.0.1:52000"))
                        .textContentType(.URL)
                        .accessibilityLabel("Host and port")
                    Button("Connect") {
                        if let endpoint = Self.endpoint(address) { connect(endpoint, address) }
                    }
                    .disabled(Self.endpoint(address) == nil)
                    .accessibilityLabel("Connect to host and port")
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { browser.stop() }
    }

    /// `host:port`, or `nil` when the text isn't one.
    static func endpoint(_ address: String) -> NWEndpoint? {
        guard let colon = address.lastIndex(of: ":") else { return nil }
        let host = address[..<colon].trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, let port = UInt16(address[address.index(after: colon)...]).flatMap(NWEndpoint.Port.init(rawValue:)) else {
            return nil
        }
        return .hostPort(host: NWEndpoint.Host(host), port: port)
    }
}

/// Asks for the code the device shows beside this Mac's name, and pairs with it.
struct ExampleRemotePairing: View {
    @ObservedObject var transport: DebugDrawerNetworkTransport
    let deviceName: String
    let paired: () -> Void
    let cancel: () -> Void
    @State private var code = ""
    @State private var isPairing = false

    var body: some View {
        Form {
            Section("Pair with \(deviceName)") {
                Text(status)
                    .foregroundStyle(.secondary)
                TextField("Code", text: $code, prompt: Text("6 digits"))
                    .textContentType(.oneTimeCode)
                    .accessibilityLabel("Pairing code")
                    .onSubmit(pair)
                HStack {
                    Button("Cancel", action: cancel)
                    Button("Pair", action: pair)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canPair)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Pairing")
            }
        }
        .formStyle(.grouped)
    }

    private var canPair: Bool {
        !isPairing && transport.pairingState == .waitingForCode && code.count == 6 && code.allSatisfy(\.isNumber)
    }

    private var status: String {
        switch transport.pairingState {
        case .connecting: "Connecting…"
        case .waitingForCode: "Type the code \(deviceName) shows for this Mac, under Remote Viewing in its drawer or Mac Viewer in its sidecar."
        case .paired: "Paired"
        case let .failed(error): "Not paired: \(error.reason). Cancel and connect again."
        }
    }

    private func pair() {
        guard canPair else { return }
        isPairing = true
        Task {
            do throws(DebugDrawerPairingError) {
                try await transport.pair(code: code)
                paired()
            } catch {
                // The status shows why, from the transport's state.
                isPairing = false
            }
        }
    }
}

/// The paired device: a sidecar's relay of a production app once the relay answers, else its
/// Network and Console, side by side, as its drawer shows them.
struct ExampleRemotePluginsView: View {
    @ObservedObject var transport: DebugDrawerNetworkTransport
    let deviceName: String
    let disconnect: () -> Void
    /// The relay's own snapshot, once a sidecar's relay answers; a debug build's drawer never does.
    @State private var relay: DebugDrawerPluginTransport<DebugDrawerSidecarRelay.Snapshot, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(deviceName, systemImage: "iphone.and.arrow.forward")
                    .font(.headline)
                Text(transport.pairingState == .paired ? "Paired" : "Disconnected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Disconnect", action: disconnect)
            }
            .padding()
            Divider()
            if let relay {
                ExampleRelayedAppView(transport: transport, relay: relay)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    column("Network", systemImage: "network") { NetworkPluginView(transport: transport) }
                    Divider()
                    column("Console", systemImage: "terminal") { ConsolePluginView(transport: transport) }
                }
            }
        }
        // Waits for as long as the window shows the device: a drawer serves no relay, so this
        // never returns there.
        .task {
            relay = try? await transport.connect(
                toPlugin: DebugDrawerSidecarRelay.pluginID, snapshot: DebugDrawerSidecarRelay.Snapshot.self, command: Never.self
            )
        }
    }

    private func column(_ title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: systemImage)
                .font(.title3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DebugDrawerPairingError {
    /// The failure, as the pairing prompt says it.
    fileprivate var reason: String {
        switch self {
        case .unreachable: "the device can't be reached"
        case .rejected: "the device rejected this Mac"
        case .wrongCode: "the code was wrong"
        case .disconnected: "the connection closed"
        case .cancelled: "cancelled"
        }
    }
}

/// A production app as a device's sidecar relays it: the app, the session it relays within, and
/// a picker of the capabilities the session shares, each drawn by the sidecar kit's own plugin over
/// the paired transport, so what the person changes here reaches the app as the sidecar's own
/// commands would. As the session ends the plugins go, since the relay serves nothing past it.
struct ExampleRelayedAppView: View {
    let transport: DebugDrawerNetworkTransport
    @ObservedObject var relay: DebugDrawerPluginTransport<DebugDrawerSidecarRelay.Snapshot, Never>
    @State private var selected: String?
    @State private var hosted: [String: AnyDebugDrawerPlugin] = [:]

    /// The kit's plugins this viewer can draw, in its order.
    private static let plugins: [DebugDrawerSidecarPlugin] = [
        .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview, .accessibilityEnvironmentOverrides,
        .analyticsEvents, .metricKitPayloads, .networkMocking, .diagnosticsCapture, .pushRegistration, .scenarios, .authActions,
        .environments, .locationSpoofing, .userDefaults, .performanceTraces, .appState
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(relay.snapshot.displayName) \(relay.snapshot.version) (\(relay.snapshot.build)), through its sidecar")
                Spacer()
                if let expires = relay.snapshot.sessionExpires {
                    Text("Session until \(expires, style: .time)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No session open on the device")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            if shared.isEmpty {
                ContentUnavailableView(
                    "Nothing Shared",
                    systemImage: "lock",
                    description: Text("The sidecar shares the app's capabilities only while a session it opened is open.")
                )
            } else {
                HStack(spacing: 0) {
                    // A list rather than segments: a production host may share a score of them.
                    List(shared, selection: shown) { plugin in
                        Label(plugin.title, systemImage: plugin.icon).tag(Optional(plugin.id))
                    }
                    .frame(width: 200)
                    .accessibilityLabel("Shared plugins")
                    Divider()
                    if let id = shown.wrappedValue, let plugin = hosted[id] {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                plugin.body
                            }
                            .padding(14)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView("Waiting for the plugin…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task(id: shown.wrappedValue) {
            guard let id = shown.wrappedValue, hosted[id] == nil,
                  let plugin = Self.plugins.first(where: { $0.id == id }) else { return }
            hosted[id] = try? await plugin.plugin(over: transport)
        }
        // A plugin the relay no longer shares is dropped, so the next session shows its own.
        .onChange(of: relay.snapshot.pluginIDs) { _, ids in
            hosted = hosted.filter { ids.contains($0.key) }
        }
    }

    /// The kit's plugins the relay shares now.
    private var shared: [DebugDrawerSidecarPlugin] {
        Self.plugins.filter { relay.snapshot.pluginIDs.contains($0.id) }
    }

    /// The plugin shown: the one picked while shared, else the first.
    private var shown: Binding<String?> {
        Binding {
            selected.flatMap { id in shared.first { $0.id == id }?.id } ?? shared.first?.id
        } set: {
            selected = $0
        }
    }
}
