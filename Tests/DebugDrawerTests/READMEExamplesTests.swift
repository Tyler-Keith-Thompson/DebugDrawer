// The README's examples, verbatim, so the README cannot drift from the code.

#if DEBUG
    import Combine
    import DebugDrawer
    import SwiftUI
    import Testing

    struct CachePlugin: DebugDrawerPlugin {
        var title = "Cache"
        var icon = "trash" // an SF Symbol

        var body: some View {
            let usage = "\(URLCache.shared.currentDiskUsage / 1024) KB"
            DebugDrawerKeyValueRow("Disk usage", value: usage)
            DebugDrawerCopyButton("Copy Usage") { usage }
            Button("Clear URL cache") { URLCache.shared.removeAllCachedResponses() }
        }
    }

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

    struct UploadsPlugin: DebugDrawerPlugin {
        var title = "Uploads"
        var icon = "arrow.up.circle"

        var body: some View {
            Text("No uploads")
        }
    }

    struct CartPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        var title = "Cart"
        var icon = "cart"

        var body: some View {
            Text("2 items")
        }

        func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            report.add(text: "2 items", named: "cart.txt")
            let checkout = Data(#"{"card":"4111","token":"t0k3n"}"#.utf8)
            report.add(jsonData: redaction.redacting(json: checkout), named: "checkout.json")
        }
    }

    struct TeamReportUploader: DebugDrawerReportUploader {
        let endpoint: URL

        func upload(_ archive: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: request, fromFile: archive)
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                throw URLError(.badServerResponse)
            }
            progress(1)
        }
    }

    /// What the sidecar sessions example registers: a log level reset at the session's end.
    @MainActor
    final class LogLevelsModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var level = "info"
        }

        enum Command: Codable, Sendable {
            case elevate
            case reset
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case .elevate: snapshot.level = "debug"
            case .reset: snapshot.level = "info"
            }
        }
    }

    /// What the sidecar sessions example registers: flag overrides kept past the session.
    @MainActor
    final class FlagOverridesModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var overrides: [String: Bool] = [:]
        }

        enum Command: Codable, Sendable {
            case override(String, Bool)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .override(flag, value): snapshot.overrides[flag] = value
            }
        }
    }

    /// Where the sidecar sessions example forwards its audit entries: kept here for the test.
    @MainActor
    enum AuditForwarder {
        static var sent: [DebugDrawerAuditEntry] = []

        static func send(_ entry: DebugDrawerAuditEntry) {
            sent.append(entry)
        }
    }

    @MainActor
    final class SidecarReceiver {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let registry: DebugDrawerModelRegistry
        let server: DebugDrawerAppGroupStoreServer
        private var forwarding: AnyCancellable?

        init(logLevels: LogLevelsModel, flags: FlagOverridesModel, container: URL) throws {
            registry = DebugDrawerModelRegistry(sessions: sessions)
            registry.register(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset))
            registry.register(flags, id: "MyApp.FlagOverrides", scope: .persistent)
            server = DebugDrawerAppGroupStoreServer(registry: registry, directory: container.appending(path: "DebugDrawer"))
            forwarding = sessions.auditEntries.sink { entry in
                AuditForwarder.send(entry)
            }
            try server.start()
        }
    }

    @MainActor
    final class FlagServiceAdapter: DebugDrawerFeatureFlagAdapter {
        private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

        func overridableFlags() -> [DebugDrawerFeatureFlag] {
            [DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false))]
        }

        func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
            overrides[key] = value
        }

        func clearOverride(forKey key: String) {
            overrides[key] = nil
        }
    }

    @MainActor
    final class ProductionReceiver {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver

        init(flags: FlagServiceAdapter, container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.featureFlagOverrides(flags))
            try receiver.start()
        }
    }

    /// The host's remote configuration, as the README's "Turning it off remotely" assumes one.
    @MainActor
    final class RemoteConfig {
        private var values: [String: Bool]
        private var handlers: [@MainActor () -> Void] = []

        init(_ values: [String: Bool]) {
            self.values = values
        }

        func bool(_ key: String) -> Bool {
            values[key] ?? false
        }

        func onUpdate(_ handler: @escaping @MainActor () -> Void) {
            handlers.append(handler)
        }

        func update(_ key: String, to value: Bool) {
            values[key] = value
            for handler in handlers {
                handler()
            }
        }
    }

    @MainActor
    final class GatedReceiver {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver

        init(config: RemoteConfig, flags: FlagServiceAdapter, container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions) {
                config.bool("sidecar_enabled")
            }
            receiver.enable(.featureFlagOverrides(flags)) { config.bool("sidecar_flag_overrides") }
            config.onUpdate { [receiver] in receiver.reevaluateGates() }
            try receiver.start()
        }
    }

    struct SessionIndicator: View {
        @ObservedObject var sessions: DebugDrawerSessions

        var body: some View {
            if let session = sessions.snapshot.session {
                HStack {
                    Text("Debug session until \(session.expires, style: .time)")
                    Button("End") { sessions.end() }
                }
            }
        }
    }

    @MainActor
    final class SidecarBackground {
        let keeper: DebugDrawerBackgroundKeeper

        init(sessions: DebugDrawerSessions, socketServer: DebugDrawerSocketServer) {
            keeper = DebugDrawerBackgroundKeeper(sessions: sessions, socketServer: socketServer)
        }

        /// From a Start Debug Session button, before switching to the sidecar.
        func startDebugSession() {
            keeper.startSession(duration: 10 * 60, title: "Debug session", subtitle: "Inspector is connected")
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test(
            "Sidecar sessions: ending a session reverts the session-scoped capability, keeps the persistent one, and the audit is forwarded",
            .timeLimit(.minutes(1))
        )
        func sidecarSessions() async throws {
            let logLevels = LogLevelsModel()
            let flags = FlagOverridesModel()
            let container = FileManager.default.temporaryDirectory.appending(path: "READMESidecar-\(UUID().uuidString)")
            AuditForwarder.sent = []
            let sut = try SidecarReceiver(logLevels: logLevels, flags: flags, container: container)
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let session = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let levels = try await sidecar.connect(
                toPlugin: "MyApp.LogLevels", snapshot: LogLevelsModel.Snapshot.self, command: LogLevelsModel.Command.self
            )
            let overrides = try await sidecar.connect(
                toPlugin: "MyApp.FlagOverrides", snapshot: FlagOverridesModel.Snapshot.self, command: FlagOverridesModel.Command.self
            )
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.commandApplied, .commandApplied, .changeReverted, .sessionEnded(.ended)]

            session.send(.open(duration: 60))
            for await state in session.snapshots() where state.isActive {
                break
            }
            levels.send(.elevate)
            overrides.send(.override("checkout", true))
            for await snapshot in overrides.snapshots() where !snapshot.overrides.isEmpty {
                break
            }
            let elevated = logLevels.snapshot.level
            sut.sessions.end()

            #expect(elevated == "debug")
            #expect(logLevels.snapshot.level == "info")
            #expect(flags.snapshot.overrides == ["checkout": true])
            #expect(Array(AuditForwarder.sent.dropFirst().map(\.event)) == expectedEvents)
            #expect(SessionIndicator(sessions: sut.sessions).sessions.snapshot == .inactive)
            sut.server.stop()
        }

        @Test(
            "Turning it off remotely: the configuration turning the gate off ends the sidecar's session and clears its override",
            .timeLimit(.minutes(1))
        )
        func gatedReceiver() async throws {
            let flags = FlagServiceAdapter()
            let config = RemoteConfig(["sidecar_enabled": true, "sidecar_flag_overrides": true])
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEGatedReceiver-\(UUID().uuidString)")
            let sut = try GatedReceiver(config: config, flags: flags, container: container)
            defer { sut.receiver.stop() }
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let session = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let overrides = try await sidecar.connect(
                toPlugin: DebugDrawerFeatureFlagOverrides.pluginID,
                snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self,
                command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.commandApplied, .changeReverted, .sessionEnded(.disabledByHost)]

            session.send(.open(duration: 60))
            for await state in session.snapshots() where state.isActive {
                break
            }
            overrides.send(.setOverride(key: "new-checkout", value: .bool(true)))
            for await snapshot in overrides.snapshots() where !snapshot.overriddenKeys.isEmpty {
                break
            }
            let overridden = flags.overrides
            config.update("sidecar_enabled", to: false)

            #expect(overridden == ["new-checkout": .bool(true)])
            #expect(flags.overrides.isEmpty)
            #expect(sut.sessions.snapshot == .inactive)
            #expect(Array(sut.sessions.auditLog.dropFirst().map(\.event)) == expectedEvents)
        }

        @Test(
            "Production builds: a sidecar overrides a flag through the receiver within a session, and ending it clears the override",
            .timeLimit(.minutes(1))
        )
        func productionReceiver() async throws {
            let flags = FlagServiceAdapter()
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEReceiver-\(UUID().uuidString)")
            let sut = try ProductionReceiver(flags: flags, container: container)
            defer { sut.receiver.stop() }
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let session = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let overrides = try await sidecar.connect(
                toPlugin: DebugDrawerFeatureFlagOverrides.pluginID,
                snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self,
                command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.commandApplied, .changeReverted, .sessionEnded(.ended)]

            session.send(.open(duration: 60))
            for await state in session.snapshots() where state.isActive {
                break
            }
            overrides.send(.setOverride(key: "new-checkout", value: .bool(true)))
            for await snapshot in overrides.snapshots() where !snapshot.overriddenKeys.isEmpty {
                break
            }
            let overridden = flags.overrides
            sut.sessions.end()

            #expect(overridden == ["new-checkout": .bool(true)])
            #expect(flags.overrides.isEmpty)
            #expect(Array(sut.sessions.auditLog.dropFirst().map(\.event)) == expectedEvents)
        }

        #if os(macOS)
            @Test("Sidecar sessions in the background: a person's start opens a session the keeper holds an activity for, and ending it lets go")
            func sidecarBackground() {
                let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
                let socketPath = FileManager.default.temporaryDirectory.appending(path: "README-\(UUID().uuidString).sock").path
                let sut = SidecarBackground(sessions: sessions, socketServer: DebugDrawerSocketServer(
                    registry: DebugDrawerModelRegistry(sessions: sessions), socketPath: socketPath
                ))
                let expectedSeconds = 10 * 60

                sut.startDebugSession()
                let during = sut.keeper.request
                let expires = sessions.snapshot.session.map { Int($0.expires.timeIntervalSince($0.opened).rounded()) }
                sessions.end()

                #expect(during == .activity)
                #expect(expires == expectedSeconds)
                #expect(sut.keeper.request == .none)
            }
        #endif

        @Test("A plugin's lifecycle, and drawers of your own")
        func lifecycleAndDrawersOfYourOwn() {
            let monitor = SocketMonitor()
            let drawer = DebugDrawer()

            drawer.registerGlobal(SocketPlugin(monitor: monitor)) // install(in:): the monitor starts
            drawer.unregisterGlobal(id: SocketPlugin(monitor: monitor).id) // uninstall(from:): it stops

            #expect(!monitor.isRunning)
            #expect(drawer.globalPlugins.isEmpty)
            drawer.registerGlobal(SocketPlugin(monitor: monitor))
            #expect(monitor.isRunning)
            // The shared drawer is read only to show it holds none of this; the test is
            // synchronous on the main actor, so no other suite's work on it runs in between.
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.title == "Sockets" })
        }

        @Test("Floating HUD")
        func floatingHUD() {
            let queue = AnyDebugDrawerPlugin(QueuePlugin())
            let uploads = AnyDebugDrawerPlugin(UploadsPlugin())

            #expect(queue.hasHUD)
            #expect(!uploads.hasHUD)
        }

        @Test("Searching plugins and actions")
        func searchingPluginsAndActions() {
            let expectedTitles = ["Expire token"]

            let actual = AnyDebugDrawerPlugin(SessionPlugin()).actions.map(\.title)

            #expect(actual == expectedTitles)
            #expect(AnyDebugDrawerPlugin(CachePlugin()).actions.isEmpty)
        }

        @Test("Disk I/O: the drawer's own file work")
        func drawerOwnFileWork() throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: "READMEDrawerWork-\(UUID().uuidString)").path
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: folder) }

            let names = try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try FileManager.default.contentsOfDirectory(atPath: folder)
            }

            #expect(names.isEmpty)
            #expect(!DebugDrawerActivity.isDrawerWork)
        }
    }

    // The README's examples that call the shared drawer (its reportUploader and redact, a plugin's
    // badges and toasts, debugDrawer()), in the serialized suite of the shared drawer's tests.
    extension SharedDrawerTests {
        @MainActor
        @Suite("README examples on the shared drawer")
        struct READMESharedDrawerExamplesTests {
            @Test("Sending reports")
            func sendingReports() throws {
                let reportsEndpoint = try #require(URL(string: "https://bugs.example.com/reports"))
                let previous = DebugDrawer.shared.reportUploader

                DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)

                let actual = DebugDrawer.shared.reportUploader as? TeamReportUploader
                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                DebugDrawer.shared.reportUploader = previous
                #expect(actual?.endpoint == reportsEndpoint)
            }

            @Test("Bug reports")
            func bugReports() throws {
                let previous = DebugDrawer.shared.redaction
                DebugDrawer.shared.redaction = .standard
                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                defer {
                    DebugDrawer.shared.unregisterGlobal(id: CartPlugin().id)
                    DebugDrawer.shared.redaction = previous
                }

                DebugDrawer.shared.registerGlobal(CartPlugin())
                let reports = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                let zip = try DebugDrawer.shared.createReport(in: reports) // the same zip the button makes

                defer { try? FileManager.default.removeItem(at: reports) }
                var contribution = DebugDrawerReport()
                CartPlugin().contribute(to: &contribution, redaction: DebugDrawer.shared.redaction)
                let checkout = try #require(contribution.files.last)
                #expect(zip.pathExtension == "zip")
                #expect(FileManager.default.fileExists(atPath: zip.path))
                #expect(contribution.files.map(\.name) == ["cart.txt", "checkout.json"])
                #expect(String(bytes: checkout.data, encoding: .utf8) == #"{"card":"4111","token":"[REDACTED]"}"#)
            }

            @Test("Usage")
            func usage() {
                let wasOpen = DebugDrawer.shared.isOpen

                // Global: registered once at startup, always in the drawer.
                DebugDrawer.shared.registerGlobal(CachePlugin())

                // The drawer, attached once to the root view.
                let root = Text("Home").debugDrawer()

                // Local: in the drawer while its view is on screen.
                let settings = Text("Settings").debugLocalPlugin(CachePlugin())

                // Open or close it from whatever trigger suits the app.
                DebugDrawer.shared.toggle()

                _ = (root, settings)
                #expect(DebugDrawer.shared.globalPlugins.contains { $0.title == "Cache" })
                #expect(DebugDrawer.shared.isOpen != wasOpen)

                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                DebugDrawer.shared.toggle()
                DebugDrawer.shared.unregisterGlobal(id: CachePlugin().id)
            }

            @Test("Badges and toasts")
            func badgesAndToasts() {
                let wasOpen = DebugDrawer.shared.isOpen
                DebugDrawer.shared.close()

                let uploads = UploadsPlugin()
                uploads.setBadge(2)
                uploads.postToast("Upload of report.pdf failed")
                let badge = DebugDrawer.shared.badges["DebugDrawerTests.UploadsPlugin"]
                let toast = DebugDrawer.shared.toast
                uploads.clearBadge()

                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                DebugDrawer.shared.dismissToast()
                if wasOpen { DebugDrawer.shared.open() }
                #expect(badge == 2)
                #expect(toast?.pluginID == "DebugDrawerTests.UploadsPlugin")
                #expect(toast?.message == "Upload of report.pdf failed")
                #expect(DebugDrawer.shared.badges["DebugDrawerTests.UploadsPlugin"] == nil)
            }

            @Test("Redacting sensitive values")
            func redactingSensitiveValues() throws {
                let previous = DebugDrawer.shared.redaction

                DebugDrawer.shared.redact(
                    headers: ["X-Api-Signature"],
                    keys: ["pin"],
                    jsonPaths: ["user.ssn", "cards.number"]
                )
                let actual = DebugDrawer.shared.redaction
                let body = Data(#"{"cards":[{"number":"4111","exp":"12/30"}],"user":{"ssn":"1"}}"#.utf8)
                let redactedBody = try #require(String(bytes: actual.redacting(json: body), encoding: .utf8))

                // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
                DebugDrawer.shared.redaction = previous
                #expect(actual.masksHeader("x-api-signature"))
                #expect(actual.masksHeader("Authorization"))
                #expect(actual.masksKey("userPin"))
                #expect(redactedBody == #"{"cards":[{"exp":"12/30","number":"[REDACTED]"}],"user":{"ssn":"[REDACTED]"}}"#)
            }
        }
    }

    #if os(macOS)
        import AppKit

        // README.md and InstallingInSwiftUI.md
        final class CacheWindowController: NSWindowController {
            override func showWindow(_ sender: Any?) {
                super.showWindow(sender)
                guard let window else { return }
                DebugDrawer.shared.registerLocal(CachePlugin(), in: window)
            }
        }

        // The window controller registers with the shared drawer, so this test stays on it, in the
        // serialized suite of the shared drawer's tests.
        extension SharedDrawerTests {
            @MainActor
            @Suite("README examples: windows")
            struct READMEWindowExamplesTests {
                @Test("A window controller registers a local plugin for its window, removed as the window closes")
                func registerLocalInWindow() {
                    // Borderless and far off screen, so showing it shows nothing.
                    let window = NSWindow(
                        contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                        styleMask: .borderless, backing: .buffered, defer: false
                    )
                    window.isReleasedWhenClosed = false
                    let sut = CacheWindowController(window: window)
                    let id = CachePlugin().id

                    sut.showWindow(nil)

                    let actualWhileOpen = DebugDrawer.shared.localPlugins.contains { $0.id == id }
                    window.close()
                    let actualAfterClosing = DebugDrawer.shared.localPlugins.contains { $0.id == id }
                    #expect(actualWhileOpen)
                    #expect(!actualAfterClosing)
                }
            }
        }
    #endif
#endif
