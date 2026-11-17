import DebugDrawer
import DebugDrawerNetworkPlugin
import Foundation
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's network calls: a greeting from an API that doesn't exist, which only a mock can
/// answer, and example.com, which the network answers unless a mock is made for it.
enum ExampleNetwork {
    /// Launched with this argument, the app adds a mock that answers the greeting, so mocking can
    /// be checked without a hand.
    static let launchArgument = "-SeedNetworkMock"
    /// `api.example.com` doesn't resolve, so without a mock the request fails.
    static let greeting = "https://api.example.com/v1/greeting"
    /// A real page, which reaches the network unless a mock matches it.
    static let page = "https://example.com/"

    #if DEBUG
        /// The mock the launch argument adds. Its id is fixed, so it is added once and the drawer's
        /// edits to it last.
        static let greetingMock = NetworkMockRule(
            id: UUID(uuidString: "6E1D3C5A-2B4F-4F7E-9A51-3C1D2E4F5A6B") ?? UUID(),
            name: "Greeting",
            matcher: .init(methods: ["GET"], host: .exact("api.example.com"), path: .wildcard("/v1/greeting*")),
            response: .init(status: 200, body: .text(#"{"message":"Hello from a mock"}"#), contentType: "application/json")
        )
    #endif

    /// Installs the Network plugin, with the greeting's mock when launched with the argument.
    @MainActor
    static func install() {
        #if DEBUG
            let seeds = ProcessInfo.processInfo.arguments.contains(launchArgument) ? [greetingMock] : []
            DebugDrawer.shared.installNetwork(mocks: seeds)
        #endif
    }

    /// The status and the start of the body of a GET to `address`, or why it failed.
    static func fetch(_ address: String) async -> String {
        guard let url = URL(string: address) else { return "Not a URL" }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = (String(bytes: data.prefix(80), encoding: .utf8) ?? "\(data.count) bytes")
                .replacingOccurrences(of: "\n", with: " ")
            return "\(status) · \(text)"
        } catch {
            return error.localizedDescription
        }
    }
}

/// Buttons that fetch the greeting and example.com, each with what came back.
struct ExampleNetworkRequests: View {
    @State private var greeting = "Not fetched"
    @State private var page = "Not fetched"

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
        }
        .accessibilityElement(children: .contain)
    }
}
