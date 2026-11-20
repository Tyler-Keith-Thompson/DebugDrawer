import CryptoKit
import Foundation

/// A public key a ``DebugDrawerSignedGrantVerifier`` trusts, with the algorithm it verifies.
///
/// Embed the grant server's public key in the app and make one from its raw bytes:
///
/// ```swift
/// let serverKey = try Curve25519.Signing.PublicKey(rawRepresentation: serverKeyBytes)
/// let verifier = DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey)])
/// ```
public enum DebugDrawerGrantPublicKey: Sendable {
    /// An Ed25519 key, for grants whose header names `"alg":"EdDSA"`.
    case ed25519(Curve25519.Signing.PublicKey)
    /// A P-256 key, for grants whose header names `"alg":"ES256"` (ECDSA with SHA-256).
    case p256(P256.Signing.PublicKey)

    /// The JWS algorithm name of a grant this key verifies.
    var algorithm: String {
        switch self {
        case .ed25519: "EdDSA"
        case .p256: "ES256"
        }
    }

    /// Whether `signature` is this key's over `signingInput`.
    func isValidSignature(_ signature: Data, for signingInput: Data) -> Bool {
        switch self {
        case let .ed25519(key):
            return key.isValidSignature(signature, for: signingInput)
        case let .p256(key):
            // JWS's ES256 signature is r and s, 32 bytes each: CryptoKit's raw representation.
            guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
            return key.isValidSignature(signature, for: signingInput)
        }
    }
}
