import Foundation

/// The host's adapter between the receiver's environment switching capability and its own
/// configuration: the hook through which a sidecar points the app at another of the host's
/// backends for a session.
///
/// The receiver calls it on the main actor, only with one of the environments the host listed as
/// it made the capability (never with anything a sidecar sent), and puts the default back as the
/// session ends, expires or a gate turns it off, and at the next launch when the app was killed
/// during one. The adapter maps the environment's ID to the host's own configuration (base URLs,
/// keys, hosts), which never leaves the app.
///
/// ```swift
/// @MainActor
/// final class BackendSwitcher: DebugDrawerEnvironmentAdapter {
///     func activate(_ environment: DebugDrawerEnvironment) {
///         switch environment.id {
///         case "staging": APIClient.shared.baseURL = AppConfig.stagingURL
///         case "canary": APIClient.shared.baseURL = AppConfig.canaryURL
///         default: APIClient.shared.baseURL = AppConfig.productionURL
///         }
///     }
/// }
/// ```
///
/// Keep the switch in memory: the receiver records which environment a session switched to and
/// puts the default back at the next launch, but a host that stores the switch itself would
/// start the next launch on that backend until then.
@MainActor
public protocol DebugDrawerEnvironmentAdapter {
    /// Points the app at `environment`'s backend until it is told otherwise.
    ///
    /// - Parameter environment: One of the environments the host listed: its default, or one it
    ///   allows a sidecar to switch to.
    func activate(_ environment: DebugDrawerEnvironment)
}
