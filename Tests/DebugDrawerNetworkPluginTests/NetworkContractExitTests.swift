// The interception contract's checks (DebugDrawerInterceptionContract). Installing registers the
// URL protocol and replaces session methods for the whole process, so each check runs in a child
// process, in a file of its own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    import DebugDrawerInterceptionContract
    @testable import DebugDrawerNetworkPlugin
    import DebugDrawerTestSupport
    import Foundation
    import ObjectiveC
    import Testing

    /// The Network plugin's side of the contract, against a loopback server of its own: each call
    /// is a GET of a path the server answers with the same response, the call's marker its path.
    @MainActor
    private struct NetworkContract: UnchangedResultContract, DrawerActivityContract {
        struct ProcessState: Equatable {
            /// The implementations of every method the plugin replaces.
            var implementations: [IMP]
            /// Whether a session made now lists the plugin's URL protocol.
            var configurationListsProtocol: Bool
        }

        /// What the app's request got back, and how many times the server served it.
        struct AppResult: Equatable {
            var status: Int
            var body: Data
            var probeHeader: String?
            var timesServed: Int
        }

        let server: ScriptedServer
        let port: UInt16

        /// Starts the server in a home folder of the child's own, as installing with
        /// `sessions: .off` deletes every session file it finds.
        static func started() async throws -> Self {
            useHomeFolderOfItsOwn()
            let body = "contract"
            let server = try ScriptedServer { _ in
                "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Probe: kept\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Connection: close\r\n\r\n\(body)"
            }
            return try await Self(server: server, port: server.start())
        }

        func install(in drawer: DebugDrawer) {
            drawer.installNetwork(sessions: .off)
        }

        func uninstall(from drawer: DebugDrawer) {
            drawer.unregisterGlobal(id: NetworkPlugin().id)
        }

        func processState() throws -> ProcessState {
            // The class the session's WebSocket tasks are, which the plugin replaces methods on.
            let probe = try URLSession(configuration: .ephemeral).webSocketTask(with: #require(URL(string: "ws://127.0.0.1")))
            let taskClass: AnyClass = type(of: probe)
            let methods = try [
                #require(class_getInstanceMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.protocolClasses))),
                #require(class_getClassMethod(URLSession.self, NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:"))),
                #require(class_getInstanceMethod(URLSession.self, NSSelectorFromString("webSocketTaskWithURL:"))),
                #require(class_getInstanceMethod(URLSession.self, NSSelectorFromString("webSocketTaskWithRequest:"))),
                #require(class_getInstanceMethod(taskClass, NSSelectorFromString("sendMessage:completionHandler:"))),
                #require(class_getInstanceMethod(taskClass, NSSelectorFromString("receiveMessageWithCompletionHandler:"))),
                #require(class_getInstanceMethod(taskClass, #selector(URLSessionWebSocketTask.cancel(with:reason:))))
            ]
            let lists = URLSessionConfiguration.default.protocolClasses?.contains { $0 == DebugNetworkProtocol.self } ?? false
            return ProcessState(implementations: methods.map(method_getImplementation), configurationListsProtocol: lists)
        }

        func makeAppCall() async throws -> AppResult {
            let path = "/app-\(UUID().uuidString)"
            let (body, response) = try await URLSession(configuration: .ephemeral).data(from: url(path))
            let http = try #require(response as? HTTPURLResponse)
            let served = server.requests.filter { $0.path == path }.count
            return AppResult(status: http.statusCode, body: body, probeHeader: http.value(forHTTPHeaderField: "X-Probe"), timesServed: served)
        }

        func limitCapture(to count: Int) {
            NetworkStore.shared.capacity = count
        }

        func makeCapturedCall(_ marker: String) async throws {
            _ = try await URLSession(configuration: .ephemeral).data(from: url("/\(marker)"))
        }

        func capturedMarkers(through marker: String) async throws -> [String] {
            for await entries in NetworkStore.shared.$entries.values where entries.contains(where: { $0.path == "/\(marker)" && $0.isComplete }) {
                break
            }
            return NetworkStore.shared.entries
                .filter { $0.host == "127.0.0.1" && !$0.path.hasPrefix("/app-") }
                .map { String($0.path.dropFirst()) }
        }

        func capturedCount() -> Int {
            NetworkStore.shared.entries.count
        }

        /// A request marked as one the plugin sends itself, as it marks the copy of each captured
        /// request it forwards.
        func makeDrawerCall(_ marker: String) async throws {
            let request = NSMutableURLRequest(url: try url("/\(marker)"))
            URLProtocol.setProperty(true, forKey: DebugNetworkProtocol.handledKey, in: request)
            _ = try await URLSession(configuration: .ephemeral).data(for: request as URLRequest)
        }

        private func url(_ path: String) throws -> URL {
            try #require(URL(string: "http://127.0.0.1:\(port)\(path)"))
        }
    }

    @Suite("The Network plugin keeps the interception contract, in a child process", .timeLimit(.minutes(1)))
    struct NetworkContractExitTests {
        @Test("Installing the Network plugin twice, or in a second drawer, changes the process as installing it once does")
        func idempotentInstall() async {
            await #expect(processExitsWith: .success) {
                try await NetworkContract.started().checkIdempotentInstall()
            }
        }

        @Test("A request is logged once with the Network plugin installed twice")
        func capturesOnceInstalledTwice() async {
            await #expect(processExitsWith: .success) {
                try await NetworkContract.started().checkCapturesOnceInstalledTwice()
            }
        }

        @Test("Removing the Network plugin from the last drawer holding it puts back what installing changed")
        func reversibleUninstall() async {
            await #expect(processExitsWith: .success) {
                try await NetworkContract.started().checkReversibleUninstall()
            }
        }

        @Test("The Network plugin removed forgets its log and logs nothing until installed again")
        func capturesNothingUninstalled() async {
            await #expect(processExitsWith: .success) {
                try await NetworkContract.started().checkCapturesNothingUninstalled()
            }
        }

        @Test("The app gets the same status, body and headers, served once, with the Network plugin installed as without")
        func unchangedResult() async {
            await #expect(processExitsWith: .success) {
                try await NetworkContract.started().checkUnchangedResult()
            }
        }

        @Test("The Network log keeps at most its capacity, the newest requests")
        func boundedCapture() async {
            await #expect(processExitsWith: .success) {
                try await NetworkContract.started().checkBoundedCapture()
            }
        }

        @Test("A request the Network plugin sends itself is never logged")
        func leavesOutDrawerActivity() async {
            await #expect(processExitsWith: .success) {
                try await NetworkContract.started().checkLeavesOutDrawerActivity()
            }
        }
    }
#endif
