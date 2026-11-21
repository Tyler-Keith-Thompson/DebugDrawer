// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import Combine
    import DebugDrawer
    @testable import DebugDrawerRemote
    import DebugDrawerTestSupport
    import Foundation
    import Network
    import SwiftUI
    import Testing
    import ViewInspector

    // The Remote Viewing plugin over a real server on 127.0.0.1 and real viewers, so a tap is
    // proven by what the viewer it names hears (rejected, disconnected) and what the others don't.
    // Each wait is for the state the step produces: the requests shown, a viewer's pairing state.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct RemoteViewingPluginTests {
        @Test("Reject on one of two requests turns that viewer away, and the other keeps waiting for its code")
        func rejectNamesItsViewer() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            defer { server.stop() }
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let first = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac A")
            for await requests in server.$pairingRequests.values where requests.count == 1 {
                break
            }
            let second = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac B")
            for await requests in server.$pairingRequests.values where requests.count == 2 {
                break
            }
            for await state in first.$pairingState.values where state == .waitingForCode {
                break
            }
            let sut = RemoteViewingPluginView(server: server)

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Reject Mac B" }.tap()
            // Whichever viewer the server turned away, so a tap that named the wrong one fails
            // rather than waits.
            for await (firstState, secondState) in first.$pairingState.combineLatest(second.$pairingState).values {
                if case .failed = firstState { break }
                if case .failed = secondState { break }
            }

            let expectedWaiting = ["Mac A"]
            #expect(second.pairingState == .failed(.rejected))
            #expect(first.pairingState == .waitingForCode)
            #expect(server.pairingRequests.map(\.viewerName) == expectedWaiting)
        }

        @Test("Disconnect on one of two paired viewers ends that viewer's connection, and the other stays paired")
        func disconnectNamesItsViewer() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            defer { server.stop() }
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let first = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac A")
            let second = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac B")
            var shown: [DebugDrawerPairingRequest] = []
            for await requests in server.$pairingRequests.values where requests.count == 2 {
                shown = requests
                break
            }
            try await first.pair(code: try #require(shown.first { $0.viewerName == "Mac A" }).code)
            try await second.pair(code: try #require(shown.first { $0.viewerName == "Mac B" }).code)
            let sut = RemoteViewingPluginView(server: server)

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Disconnect Mac B" }.tap()
            // Whichever viewer the server turned away, so a tap that named the wrong one fails
            // rather than waits.
            for await (firstState, secondState) in first.$pairingState.combineLatest(second.$pairingState).values {
                if case .failed = firstState { break }
                if case .failed = secondState { break }
            }

            let expectedPaired = ["Mac A"]
            #expect(second.pairingState == .failed(.disconnected))
            #expect(first.pairingState == .paired)
            #expect(server.pairedViewers.map(\.name) == expectedPaired)
        }

        @Test("Each request shows its viewer's name and its code, read out digit by digit")
        func requestShowsNameAndCode() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            defer { server.stop() }
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let viewer = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Studio Mac")
            var shown: DebugDrawerPairingRequest?
            for await requests in server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            let request = try #require(shown)
            for await state in viewer.$pairingState.values where state == .waitingForCode {
                break
            }
            let sut = RemoteViewingPluginView(server: server)

            let row = try sut.inspect().find(RemotePairingRequestRow.self)
            let actualRequest = try row.actualView().request
            let actualCode = try row.find(text: String(request.code.prefix(3)) + " " + String(request.code.suffix(3)))
            let actualCodeLabel = try actualCode.accessibilityLabel().string()

            let expectedCodeLabel = "Code " + request.code.map(String.init).joined(separator: " ")
            #expect(actualRequest == request)
            #expect(try row.find(text: "Studio Mac").string() == "Studio Mac")
            #expect(actualCodeLabel == expectedCodeLabel)
            #expect(viewer.pairingState == .waitingForCode)
        }

        @Test("Listening on loopback, the plugin shows the port, 127.0.0.1 alone and no Bonjour, with Stop Serving")
        func listeningShowsPort() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            defer { server.stop() }
            let port = try #require(server.port)
            let sut = RemoteViewingPluginView(server: server)

            let actual = try sut.inspect().find(RemoteViewingView.self).actualView().state
            let view = try sut.inspect()

            let expected = RemoteServingState.listening(port: port, loopbackOnly: true, advertises: false)
            #expect(actual == expected)
            #expect(try view.find(text: "Listening").string() == "Listening")
            #expect(try view.find(text: String(port)).string() == String(port))
            #expect(try view.find(text: "127.0.0.1 only").string() == "127.0.0.1 only")
            #expect(try view.find(text: "Not advertised").string() == "Not advertised")
            #expect(throws: Never.self) { try view.find(button: "Stop Serving") }
            #expect(throws: (any Error).self) { try view.find(button: "Start Serving") }
        }

        @Test("Stop Serving stops the server, which disconnects a viewer waiting for its code")
        func stopServing() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            defer { server.stop() }
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let viewer = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Studio Mac")
            for await requests in server.$pairingRequests.values where !requests.isEmpty {
                break
            }
            let sut = RemoteViewingPluginView(server: server)

            try sut.inspect().find(button: "Stop Serving").tap()
            for await state in viewer.$pairingState.values {
                if case .failed = state { break }
            }

            #expect(server.isRunning == false)
            #expect(server.pairingRequests.isEmpty)
            #expect(viewer.pairingState == .failed(.disconnected))
        }

        @Test("Not yet started, the plugin says so, offers Start Serving and lists no requests; Start Serving starts the server")
        func startServing() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            defer { server.stop() }
            let sut = RemoteViewingPluginView(server: server)
            let before = try sut.inspect()
            let stateBefore = try before.find(RemoteViewingView.self).actualView().state
            let statusBefore = try before.find(text: "Not listening").string()
            let listsRequests = (try? before.find(text: "Pairing requests")) != nil

            try before.find(button: "Start Serving").tap()
            for await port in server.$port.values where port != nil {
                break
            }

            #expect(stateBefore == .stopped)
            #expect(statusBefore == "Not listening")
            #expect(listsRequests == false)
            #expect(server.isRunning)
        }

        @Test("A start that failed shows why, and Start Serving stays to try again")
        func failedStartShowsReason() throws {
            let reason = "The system refused to listen on port 8080."
            let sut = RemoteViewingView(
                state: .failed(reason), requests: [], viewers: [],
                actions: RemoteViewingActions(start: {}, stop: {}, reject: { _ in }, disconnect: { _ in })
            )

            let view = try sut.inspect()

            #expect(try view.find(text: reason).string() == reason)
            #expect(try view.find(text: "Couldn't start serving").string() == "Couldn't start serving")
            #expect(try view.find(text: "Not listening").string() == "Not listening")
            #expect(throws: Never.self) { try view.find(button: "Start Serving") }
        }

        @Test("While starting, Start Serving is disabled")
        func startingDisablesStart() throws {
            let sut = RemoteViewingView(
                state: .starting, requests: [], viewers: [],
                actions: RemoteViewingActions(start: {}, stop: {}, reject: { _ in }, disconnect: { _ in })
            )

            let actual = try sut.inspect().find(button: "Start Serving").isDisabled()

            #expect(actual)
            #expect(try sut.inspect().find(text: "Starting…").string() == "Starting…")
        }

        @Test("Listening with nobody asking or paired, both lists say they are empty")
        func emptyLists() throws {
            let sut = RemoteViewingView(
                state: .listening(port: 52_814, loopbackOnly: false, advertises: true), requests: [], viewers: [],
                actions: RemoteViewingActions(start: {}, stop: {}, reject: { _ in }, disconnect: { _ in })
            )

            let view = try sut.inspect()

            #expect(try view.find(text: "No viewer is asking to pair.").string() == "No viewer is asking to pair.")
            #expect(try view.find(text: "No viewer is paired.").string() == "No viewer is paired.")
            #expect(try view.find(text: "Every interface").string() == "Every interface")
            #expect(try view.find(text: "Advertised").string() == "Advertised")
        }

        @Test("The badge counts the requests waiting in the drawer that installed the plugin, and in no other")
        func badgeCountsRequests() async throws {
            let suite = temporarySuiteName("RemoteViewingPluginTests.badgeCountsRequests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            defer { server.stop() }
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let first = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac A")
            for await requests in server.$pairingRequests.values where requests.count == 1 {
                break
            }
            let sut = RemoteViewingPlugin(server: server)

            drawer.registerGlobal(sut)
            let installed = drawer.badges[sut.id]
            let second = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac B")
            for await requests in server.$pairingRequests.values where requests.count == 2 {
                break
            }
            let twoWaiting = drawer.badges[sut.id]
            server.reject(try #require(server.pairingRequests.first { $0.viewerName == "Mac A" }))
            let oneWaiting = drawer.badges[sut.id]
            let sharedWhileInstalled = DebugDrawer.shared.badges[sut.id]
            drawer.unregisterGlobal(id: sut.id)
            server.reject(try #require(server.pairingRequests.first))

            #expect(installed == 1)
            #expect(twoWaiting == 2)
            #expect(oneWaiting == 1)
            #expect(sharedWhileInstalled == nil)
            #expect(drawer.badges[sut.id] == nil)
            #expect(DebugDrawer.shared.badges[sut.id] == nil)
            withExtendedLifetime((first, second)) {}
        }
    }
#endif
