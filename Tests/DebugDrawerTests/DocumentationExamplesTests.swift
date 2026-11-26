// The DocC articles' examples (Sources/DebugDrawer/DebugDrawer.docc), verbatim, so the articles
// cannot drift from the code. Examples an article shares with the README are pinned in
// READMEExamplesTests.swift.

#if DEBUG
    import DebugDrawer
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing

    // InstallingInSwiftUI.md
    struct OrdersApp: App {
        init() {
            DebugDrawer.shared.registerGlobal(CachePlugin())
        }

        var body: some Scene {
            WindowGroup {
                OrdersRootView()
                    .debugDrawer()
            }
        }
    }

    // InstallingInSwiftUI.md
    struct OrdersRootView: View {
        var body: some View {
            Text("Orders")
                .onTapGesture(count: 3) {
                    DebugDrawer.shared.toggle()
                }
        }
    }

    // WritingPlugins.md
    struct OrderPlugin: DebugDrawerPlugin {
        let orderID: String

        var title = "Order"
        var icon = "shippingbox"

        var body: some View {
            DebugDrawerKeyValueRow("Order ID", value: orderID)
        }
    }

    // WritingPlugins.md
    struct OrderDetailView: View {
        let orderID: String

        var body: some View {
            Text("Order \(orderID)")
                .debugLocalPlugin(OrderPlugin(orderID: orderID))
        }
    }

    // WritingPlugins.md
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

    // BuildingPluginViews.md
    struct ServerSettingsView: View {
        @State private var usesStaging = false

        var body: some View {
            DebugDrawerSection("Server") {
                DebugDrawerRow("Use staging", systemImage: "server.rack", isOn: $usesStaging)
                DebugDrawerKeyValueRow("Host", value: usesStaging ? "staging.example.com" : "api.example.com")
                DebugDrawerKeyValueRow("API key", value: "k-12345", redacted: DebugDrawerRedaction.mask)
            } footer: {
                Text("Applies to the next request.")
            }
            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy Host") { usesStaging ? "staging.example.com" : "api.example.com" }
                Button("Reconnect") {}
            } trailing: {
                Button("Sign Out", role: .destructive) {}
                    .debugDrawerButtonStyle(.destructive)
            }
        }
    }

    /// An event the WritingPlugins.md example captures.
    struct AnalyticsEvent: Sendable {
        let name: String
        let payload: Data
    }

    // WritingPlugins.md
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

    // WritingPlugins.md
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

    // WritingPlugins.md
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

    // WritingPlugins.md
    struct CounterPlugin: DebugDrawerPlugin {
        let model: CounterModel
        var title = "Counter"
        var icon = "number.circle"

        var body: some View {
            CounterView(transport: .direct(to: model))
        }
    }

    // WritingPlugins.md
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

    // WritingPlugins.md
    @MainActor
    func counterTransport(group: DebugDrawerAppGroupContainer, app bundleIdentifier: String) async throws
        -> DebugDrawerPluginTransport<CounterModel.Snapshot, CounterModel.Command> {
        let sidecar = try DebugDrawerSidecarTransport(
            socketPath: group.socketPath(of: bundleIdentifier), storeDirectory: group.appDirectory(of: bundleIdentifier)
        )
        return try await sidecar.connect(toPlugin: "MyApp.CounterPlugin", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)
    }

    @MainActor
    @Suite("Documentation examples")
    struct DocumentationExamplesTests {
        // The container stands in for an app group's: a directory in the test's temporary one,
        // however long its path. The transport's first snapshot may come from the store, before
        // the app's hello arrives over the socket; a command lands either way.
        @Test(
            "Writing plugins: a sidecar's transport carries a command while the app serves the socket, and another once it stops",
            .timeLimit(.minutes(1))
        )
        func modelFromAnotherProcess() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "DocumentationExamplesTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug") { _ in container }
            let model = CounterModel()
            let sharing = try CounterSharing(model: model, group: group)

            let sut = try await counterTransport(group: group, app: AppPresence.Identity.of(.main).bundleIdentifier)
            sut.send(.increment)
            for await snapshot in sut.snapshots() where snapshot.count == 1 {
                break
            }
            sharing.socketServer.stop()
            sut.send(.increment)
            for await snapshot in sut.snapshots() where snapshot.count == 2 {
                break
            }

            #expect(model.snapshot.count == 2)
            sharing.storeServer.stop()
        }

        @Test("Writing plugins: commands sent through a direct transport change the model, and its snapshot round-trips through JSON")
        func modelApartFromTheView() throws {
            let model = CounterModel()
            let sut = DebugDrawerPluginTransport.direct(to: model)
            let expected = CounterModel.Snapshot(count: 2)

            sut.send(.increment)
            sut.send(.increment)
            let actual = try JSONDecoder().decode(CounterModel.Snapshot.self, from: JSONEncoder().encode(sut.snapshot))

            #expect(actual == expected)
            #expect(model.snapshot == expected)
            #expect(AnyDebugDrawerPlugin(CounterPlugin(model: model)).title == "Counter")
        }

        @Test("Writing plugins: a store keeps its events in a capture buffer and counts the ones it dropped")
        func captureBuffer() throws {
            let sut = try EventStore()
            let expected = ["opened", "closed"]

            for name in ["launched", "opened", "closed"] {
                sut.record(AnalyticsEvent(name: name, payload: Data(repeating: 0, count: 524_288)))
            }
            sut.refresh()

            #expect(sut.events.map(\.name) == expected)
            #expect(sut.droppedCount == 1)
        }

        @Test("Writing plugins: a local plugin's ID is its type's fully qualified name")
        func localPlugin() {
            let sut = OrderPlugin(orderID: "42")
            let expectedID = "DebugDrawerTests.OrderPlugin"

            let actual = AnyDebugDrawerPlugin(sut)

            #expect(actual.id == expectedID)
        }

        @Test("Writing plugins: a stale local registration's token leaves the newer one in place")
        func localPluginTokens() throws {
            let suite = temporarySuiteName("DocumentationExamplesTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let id = "DebugDrawerTests.OrderPlugin"
            let expected = [id]
            let stale = sut.registerLocal(OrderPlugin(orderID: "1"))
            let current = sut.registerLocal(OrderPlugin(orderID: "2"))

            sut.unregisterLocal(id: id, token: stale)

            let actual = sut.localPlugins.map(\.id)
            sut.unregisterLocal(id: id, token: current)
            #expect(actual == expected)
            #expect(sut.localPlugins.isEmpty)
        }

        @Test("Writing plugins: a plugin declares its category, header accessory and HUD readout")
        func headerAndHUD() {
            let expectedCategory = "Background"

            let actual = AnyDebugDrawerPlugin(JobsPlugin())

            #expect(actual.category == expectedCategory)
            #expect(actual.headerAccessory != nil)
            #expect(actual.hasHUD)
        }
    }

    // The articles' examples that call the shared drawer (an app's init registering with it, the
    // release-build calls), in the serialized suite of the shared drawer's tests.
    extension SharedDrawerTests {
        @MainActor
        @Suite("Documentation examples on the shared drawer")
        struct DocumentationSharedDrawerExamplesTests {
            @Test("Installing in SwiftUI: the app registers its global plugins when it starts")
            func installingInSwiftUI() {
                let expectedTitle = "Cache"

                _ = OrdersApp()

                let actual = DebugDrawer.shared.globalPlugins.map(\.title)
                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                DebugDrawer.shared.unregisterGlobal(id: CachePlugin().id)
                #expect(actual.contains(expectedTitle))
            }

            @Test("Release builds: the calls that set the drawer up need no #if DEBUG")
            func releaseBuilds() throws {
                let reportsEndpoint = try #require(URL(string: "https://bugs.example.com/reports"))
                let previous = DebugDrawer.shared.reportUploader

                DebugDrawer.shared.registerGlobal(CachePlugin())
                DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)

                let actual = DebugDrawer.shared.reportUploader as? TeamReportUploader
                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                DebugDrawer.shared.reportUploader = previous
                DebugDrawer.shared.unregisterGlobal(id: CachePlugin().id)
                #expect(actual?.endpoint == reportsEndpoint)
            }
        }
    }

    // Views render on the Mac; ViewInspector is linked on Apple platforms only.
    #if os(macOS)
        import AppKit
        import ViewInspector

        // InstallingInSwiftUI.md
        final class InvoiceWindowController: NSWindowController {
            @objc func toggleDebugDrawer(_: Any?) {
                guard let window else { return }
                DebugDrawer.shared.toggle(in: window)
            }
        }

        // The window controller opens the shared drawer, so this test stays on it, in the serialized
        // suite of the shared drawer's tests.
        extension SharedDrawerTests {
            @MainActor
            @Suite("Documentation examples: windows")
            struct DocumentationWindowExamplesTests {
                @Test("Installing in SwiftUI: a window controller opens the drawer in its own window, attaching it first")
                func toggleInWindow() throws {
                    // Borderless and far off screen: ordered in, so the drawer's panel can be, but never seen.
                    let window = NSWindow(
                        contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                        styleMask: .borderless, backing: .buffered, defer: false
                    )
                    window.isReleasedWhenClosed = false
                    window.orderFront(nil)
                    defer { window.close() }
                    let sut = InvoiceWindowController(window: window)

                    sut.toggleDebugDrawer(nil)

                    // The drawer's panel is a child window of the window it opens in.
                    let actual = window.childWindows?.contains(where: \.isVisible) == true
                    DebugDrawer.shared.toggle(in: window)
                    #expect(actual)
                }
            }
        }

        @MainActor
        @Suite("Documentation examples: views")
        struct DocumentationViewExamplesTests {
            @Test("Building a plugin's view: the settings view shows its rows, masks the key and offers its actions")
            func buildingPluginViews() throws {
                let sut = ServerSettingsView()
                let expectedTexts: Set = [
                    "Server", "Use staging", "Host", "api.example.com", "API key", DebugDrawerRedaction.mask,
                    "Applies to the next request.", "Reconnect", "Sign Out"
                ]
                let secret = "k-12345"

                let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

                #expect(expectedTexts.isSubset(of: Set(actual)))
                #expect(!actual.contains(secret))
            }
        }
    #endif
#endif
