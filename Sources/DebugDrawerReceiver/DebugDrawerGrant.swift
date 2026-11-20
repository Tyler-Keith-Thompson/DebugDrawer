import Foundation

// What a verified grant says, whatever format it arrived in: a verifier turns a token into this,
// and the sessions enforce it (audience, validity window, single use, capabilities), so a company
// that brings its own format writes only the part that checks the signature and reads the fields,
// never the policy. It holds nothing secret: the token and its signature stay behind in the
// verifier, so a session's snapshot can carry the grant and the audit log can name it.

/// What a verified grant allows: who holds it, which app it is for, which capabilities it covers
/// and when it is valid.
///
/// A ``DebugDrawerGrantVerifier`` makes one from a token it has authenticated; the sessions then
/// check it against their ``DebugDrawerGrantPolicy``. An open session carries it as
/// ``DebugDrawerSession/grant``.
public struct DebugDrawerGrant: Codable, Equatable, Sendable {
    /// Tells this grant from every other the issuer made: a session opens at most once with it.
    public let id: String
    /// Who it was issued to, such as the employee who signed in to the sidecar.
    public let subject: String
    /// The apps it is for: the receiver's ``DebugDrawerGrantPolicy/audience`` must be one of them.
    public let audiences: [String]
    /// The IDs of the capabilities a session opened with it may drive.
    public let capabilities: [String]
    /// When it becomes valid.
    public let notBefore: Date
    /// When it stops being valid; a session opened with it expires then at the latest.
    public let expires: Date

    /// A grant.
    ///
    /// - Parameters:
    ///   - id: Tells it from every other grant the issuer made.
    ///   - subject: Who it was issued to.
    ///   - audiences: The apps it is for.
    ///   - capabilities: The IDs of the capabilities it covers.
    ///   - notBefore: When it becomes valid.
    ///   - expires: When it stops being valid.
    public init(id: String, subject: String, audiences: [String], capabilities: [String], notBefore: Date, expires: Date) {
        self.id = id
        self.subject = subject
        self.audiences = audiences
        self.capabilities = capabilities
        self.notBefore = notBefore
        self.expires = expires
    }
}
