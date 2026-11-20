import Foundation

/// What a conditioning profile did to a request: which profile, the latency it added, the
/// bandwidth it capped the response at, and the failure it ended the request with, if any.
public struct NetworkConditionEffect: Hashable, Codable, Sendable {
    /// The name of the profile that applied.
    public let profileName: String
    /// How long the request waited before it was answered or sent.
    public let latency: Duration
    /// The most bytes a second the response's body arrived at, or `nil` for no cap.
    public let bandwidth: Int?
    /// How the profile failed the request, or `nil` when it let the request through.
    public let failure: NetworkConditionProfile.Failure?

    /// What a profile did to one request.
    ///
    /// - Parameters:
    ///   - profileName: The name of the profile that applied.
    ///   - latency: How long the request waited.
    ///   - bandwidth: The cap its body arrived at, or `nil`.
    ///   - failure: How the profile failed it, or `nil`.
    package init(profileName: String, latency: Duration, bandwidth: Int?, failure: NetworkConditionProfile.Failure?) {
        self.profileName = profileName
        self.latency = latency
        self.bandwidth = bandwidth
        self.failure = failure
    }
}
