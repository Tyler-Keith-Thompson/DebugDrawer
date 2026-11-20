import Foundation

// An environment is a name the host gave one of its own backends, and nothing else: an ID, a
// title and a summary. It holds no URL, host or configuration on purpose. The host maps the ID to
// its own configuration in its adapter, so neither the wire format nor this value has a field an
// address could travel in, and a sidecar (a leaked one included) can only pick a backend the
// host's source lists. Rejected: a base URL on the value for the sidecar to show (it would cross
// to the sidecar, and a field that can hold a URL is a field a later change might read), and a
// generic payload of the host's (its Codable form would decide what crosses).

/// One of the host's backends a sidecar may switch a production app to: the ID the host's
/// ``DebugDrawerEnvironmentAdapter`` maps to its own configuration, and the title and summary a
/// sidecar lists it with.
///
/// It holds no URL or address: the host keeps those in its adapter, so nothing a sidecar sends or
/// reads can name a backend the app doesn't already know.
///
/// ```swift
/// DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build")
/// ```
public struct DebugDrawerEnvironment: Codable, Equatable, Sendable, Identifiable {
    /// The ID a sidecar asks for it by and the adapter maps to the host's configuration.
    public let id: String
    /// The name a sidecar lists it under.
    public let title: String
    /// What it is, as a sidecar shows it under the title; empty for none.
    public let summary: String

    /// An environment of the host's.
    ///
    /// Traps when `id` is empty.
    ///
    /// - Parameters:
    ///   - id: The ID a sidecar asks for it by; it must differ from every other environment's.
    ///   - title: The name a sidecar lists it under.
    ///   - summary: What it is, shown under the title.
    public init(_ id: String, title: String, summary: String = "") {
        precondition(!id.isEmpty, "An environment's ID is empty")
        self.id = id
        self.title = title
        self.summary = summary
    }
}
