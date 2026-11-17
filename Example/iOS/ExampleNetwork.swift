import DebugDrawer
import DebugDrawerNetworkPlugin
import Foundation
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's network calls: a greeting from an API that doesn't exist, which only a mock can
/// answer, example.com, which the network answers unless a mock is made for it, an order
/// POSTed to the same API, whose resend asks before it is sent, GraphQL queries to the same API,
/// which the log names by operation, and a burst of analytics events, noise to ignore.
enum ExampleNetwork {
    /// Launched with this argument, the app adds mocks that answer the greeting, the order, the
    /// GraphQL queries and the analytics events, so mocking can be checked without a hand.
    static let launchArgument = "-SeedNetworkMock"
    /// Launched with this argument, the app adds a profile that slows example.com by two seconds,
    /// and one, off, that fails the greeting with no connection, and pins Network to the HUD, so
    /// conditioning can be checked without a hand.
    static let conditionArgument = "-SeedNetworkCondition"
    /// Launched with this argument and a number, `-NetworkSessionsKept 2`, the app keeps that many
    /// earlier launches' requests rather than five, so pruning can be checked by relaunching.
    static let sessionsArgument = "-NetworkSessionsKept"
    /// `api.example.com` doesn't resolve, so without a mock the request fails.
    static let greeting = "https://api.example.com/v1/greeting"
    /// A real page, which reaches the network unless a mock matches it.
    static let page = "https://example.com/"
    /// Orders are POSTed to the API that doesn't exist, so without a mock the request fails.
    static let orders = "https://api.example.com/v1/orders"
    /// GraphQL requests are POSTed to the same API, so without a mock they fail; the log names
    /// each by its operation either way.
    static let graphQL = "https://api.example.com/graphql"
    /// An analytics collector that doesn't exist, standing in for the SDKs whose events bury an
    /// app's own requests; a mock answers it.
    static let analytics = "https://collect.analytics.example.net/v1/events"

    /// The mock the launch argument adds. Its id is fixed, so it is added once and the drawer's
    /// edits to it last.
    static let greetingMock = NetworkMockRule(
        id: UUID(uuidString: "6E1D3C5A-2B4F-4F7E-9A51-3C1D2E4F5A6B") ?? UUID(),
        name: "Greeting",
        matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/greeting*")),
        response: .init(status: 200, body: .text(#"{"message":"Hello from a mock"}"#), contentType: "application/json")
    )

    /// The mock the launch argument adds for the order, with a fixed id like the greeting's.
    static let orderMock = NetworkMockRule(
        id: UUID(uuidString: "9A3C5E71-4B2D-4F86-A1E9-6D7B8C0F2A35") ?? UUID(),
        name: "Place order",
        matcher: .init(methods: ["POST"], host: .exact("api.example.com"), path: .exact("/v1/orders")),
        response: .init(status: 201, body: .text(#"{"id":7,"status":"placed"}"#), contentType: "application/json")
    )

    /// The mock the launch argument adds for GraphQL: every POST to /graphql gets a user.
    static let graphQLMock = NetworkMockRule(
        id: UUID(uuidString: "3D8F1B6A-5C2E-4A97-B0D4-7E9A1C3F5B28") ?? UUID(),
        name: "GraphQL",
        matcher: .init(methods: ["POST"], host: .exact("api.example.com"), path: .exact("/graphql")),
        response: .init(status: 200, body: .text(#"{"data":{"user":{"id":"1","name":"Ada"}}}"#), contentType: "application/json")
    )

    /// The mock the launch argument adds for the analytics events, which it accepts.
    static let analyticsMock = NetworkMockRule(
        id: UUID(uuidString: "C61E2A94-7B3F-4D85-9A0C-2F4E6B8D1A73") ?? UUID(),
        name: "Analytics",
        matcher: .init(methods: ["POST"], host: .wildcard("*.analytics.example.net")),
        response: .init(status: 202, body: .text(#"{"accepted":true}"#), contentType: "application/json")
    )

    /// The profiles the condition argument adds, with fixed ids, so they are added once and the
    /// drawer's edits to them last.
    static let conditionSeeds = [
        NetworkConditionProfile(
            id: UUID(uuidString: "0B7E4C2A-9D31-4A6F-8E25-1C3B5D7F9A02") ?? UUID(),
            name: "Slow example.com",
            host: .exact("example.com"),
            latency: .seconds(2)
        ),
        NetworkConditionProfile(
            id: UUID(uuidString: "4F2A9C61-3E7B-4D58-B1A6-8C0E2D4F6B13") ?? UUID(),
            name: "Greeting offline",
            isEnabled: false,
            host: .exact("api.example.com"),
            failureRate: 100,
            failure: .notConnectedToInternet
        )
    ]

    /// Installs the Network plugin, with the greeting's mock, the profiles and the number of
    /// sessions kept when launched with their arguments.
    @MainActor
    static func install() {
        let arguments = ProcessInfo.processInfo.arguments
        let mocks = arguments.contains(launchArgument) ? [greetingMock, orderMock, graphQLMock, analyticsMock] : []
        let conditions = arguments.contains(conditionArgument) ? conditionSeeds : []
        let kept = arguments.firstIndex(of: sessionsArgument)
            .flatMap { arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil }
            .map { max($0, 0) }
        let sessions = kept.map { NetworkSessionPersistence(maxSessions: $0) } ?? .standard
        DebugDrawer.shared.installNetwork(mocks: mocks, conditions: conditions, sessions: sessions)
        if !conditions.isEmpty, !DebugDrawer.shared.hudLayout.pinned.contains(NetworkPlugin().id) {
            DebugDrawer.shared.toggleHUD(forPlugin: NetworkPlugin().id)
        }
    }

    /// The status, the start of the body and the time of a GET to `address`, or why it failed and
    /// when.
    static func fetch(_ address: String) async -> String {
        guard let url = URL(string: address) else { return "Not a URL" }
        return await send(URLRequest(url: url))
    }

    /// The status, the start of the body and the time of a POST of an order for tea, or why it
    /// failed and when. It carries a made-up bearer token, which the drawer masks in Copy cURL and
    /// HAR exports.
    static func placeOrder() async -> String {
        guard let url = URL(string: orders) else { return "Not a URL" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer example-token", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"item":"tea","quantity":1}"#.utf8)
        return await send(request)
    }

    /// Runs two GraphQL operations: GetUser, named by `operationName`, and UpdateUser, a mutation
    /// named only in its query. Returns the first's answer, or why it failed.
    static func runGraphQL() async -> String {
        let getUser = #"{"operationName":"GetUser","query":"query GetUser($id: ID!) { user(id: $id) { name } }","variables":{"id":"1"}}"#
        let updateUser = #"{"query":"mutation UpdateUser($name: String!) { updateUser(name: $name) { id } }","variables":{"name":"Ada"}}"#
        let answer = await post(getUser, to: graphQL)
        _ = await post(updateUser, to: graphQL)
        return answer
    }

    /// POSTs three analytics events, the noise an SDK sends, and returns the last answer, or why it
    /// failed.
    static func sendAnalytics() async -> String {
        let events = ["app_open", "screen_view", "button_tap"]
        var answer = ""
        for event in events {
            answer = await post(#"{"event":"\#(event)"}"#, to: analytics)
        }
        return answer
    }

    private static func post(_ body: String, to address: String) async -> String {
        guard let url = URL(string: address) else { return "Not a URL" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return await send(request)
    }

    private static func send(_ request: URLRequest) async -> String {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = (String(bytes: data.prefix(80), encoding: .utf8) ?? "\(data.count) bytes")
                .replacingOccurrences(of: "\n", with: " ")
            return "\(status) in \(milliseconds(since: start, on: clock)) · \(text)"
        } catch {
            return "\(error.localizedDescription) (after \(milliseconds(since: start, on: clock)))"
        }
    }

    /// The time since `start`, in whole milliseconds: "2,013 ms".
    private static func milliseconds(since start: ContinuousClock.Instant, on clock: ContinuousClock) -> String {
        let (seconds, attoseconds) = (clock.now - start).components
        return "\((seconds * 1000 + attoseconds / 1_000_000_000_000_000).formatted()) ms"
    }
}

/// Buttons that fetch the greeting and example.com, place an order, run GraphQL queries and send
/// analytics events, each with what came back.
struct ExampleNetworkRequests: View {
    @State private var greeting = "Not fetched"
    @State private var page = "Not fetched"
    @State private var order = "Not placed"
    @State private var graphQL = "Not run"
    @State private var analytics = "Not sent"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Fetch Greeting") {
                Task { greeting = await ExampleNetwork.fetch(ExampleNetwork.greeting) }
            }
            Text(greeting)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Greeting response: \(greeting)")
            Button("Fetch example.com") {
                Task { page = await ExampleNetwork.fetch(ExampleNetwork.page) }
            }
            Text(page)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityLabel("example.com response: \(page)")
            Button("Place Order") {
                Task { order = await ExampleNetwork.placeOrder() }
            }
            Text(order)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Order response: \(order)")
            Button("Run GraphQL Queries") {
                Task { graphQL = await ExampleNetwork.runGraphQL() }
            }
            Text(graphQL)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityLabel("GraphQL response: \(graphQL)")
            Button("Send Analytics Events") {
                Task { analytics = await ExampleNetwork.sendAnalytics() }
            }
            Text(analytics)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Analytics response: \(analytics)")
        }
        .accessibilityElement(children: .contain)
    }
}
