import Foundation

/// Authenticates a grant token and reads what it allows.
///
/// ``DebugDrawerSignedGrantVerifier`` reads DebugDrawer's own format. Conform to bring another:
/// check the token's signature with a key the app embeds, then return its fields. Leave the
/// policy to the sessions: they check the audience, the validity window, single use and the
/// capabilities of what you return. Return a grant only for a token you authenticated, and give
/// each grant an ``DebugDrawerGrant/id`` its issuer never reuses.
public protocol DebugDrawerGrantVerifier: Sendable {
    /// The grant `token` carries, once its signature is checked.
    ///
    /// - Parameter token: The token a sidecar sent with
    ///   ``DebugDrawerSessionCommand/open(duration:grant:)``, as it arrived: untrusted input.
    /// - Returns: What the grant allows.
    /// - Throws: ``DebugDrawerGrantVerificationError/malformed`` for a token that can't be read,
    ///   ``DebugDrawerGrantVerificationError/invalidSignature`` for one no trusted key signed.
    func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant
}

/// Why a ``DebugDrawerGrantVerifier`` rejected a token. The sessions audit either as
/// ``DebugDrawerAuditEntry/Refusal/grantInvalid``.
public enum DebugDrawerGrantVerificationError: Error, Equatable, Sendable {
    /// The token isn't in the verifier's format, or is missing a field.
    case malformed
    /// No key the verifier trusts signed the token, as it is, with the algorithm it names.
    case invalidSignature
}
