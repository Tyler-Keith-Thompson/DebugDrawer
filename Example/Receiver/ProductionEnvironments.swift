import Combine
import DebugDrawerReceiver
import Foundation

/// The example's backends, Production, Staging and Canary, which a sidecar switches between for
/// its session through the environment switching capability: the model the receiver serves and
/// the session indicator reads, over the backend it switches. The sidecar sees only each
/// environment's ID, title and summary; the base URLs stay in the backend.
@MainActor
final class ProductionEnvironments {
    static let production = DebugDrawerEnvironment("production", title: "Production")
    static let staging = DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build")
    static let canary = DebugDrawerEnvironment("canary", title: "Canary", summary: "The next release, on 5% of servers")

    /// The base URL the app's requests go to, switched by the model.
    let backend: ProductionBackend
    /// The environments a sidecar may pick. Made as the app starts, so a switch a killed session
    /// left is undone before the app's first request.
    let model: DebugDrawerEnvironments

    init() {
        let backend = ProductionBackend()
        self.backend = backend
        model = DebugDrawerEnvironments(default: Self.production, allowing: Self.staging, Self.canary, adapter: backend)
    }
}

/// The app's API configuration: each environment's base URL, by ID, and the one in use. Fake
/// hosts: nothing answers at them.
@MainActor
final class ProductionBackend: ObservableObject, DebugDrawerEnvironmentAdapter {
    private static let baseURLs = [
        "production": "https://api.example.com",
        "staging": "https://staging.api.example.com",
        "canary": "https://canary.api.example.com"
    ]

    /// The base URL the app's requests go to now.
    @Published private(set) var baseURL = ProductionBackend.baseURLs["production"] ?? ""

    func activate(_ environment: DebugDrawerEnvironment) {
        baseURL = Self.baseURLs[environment.id] ?? baseURL
    }
}
