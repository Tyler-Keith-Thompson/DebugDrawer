import CryptoKit
import DebugDrawerReceiver
import DebugDrawerSidecarKit
import Foundation

/// Stands in for the company's grant server, in the sidecar itself: it signs, with RFC 8037's
/// published Ed25519 test key, a grant for the app picked, to `tester@example.com`, for 15
/// minutes, listing every capability the app serves. A company's sidecar signs the person in and
/// asks its server instead, which keeps the private key; the host trusts only the public key
/// (ExampleGrantKey in Example/Receiver). The signing is the README's `DebugDrawerTestGrantSigner`.
enum ExampleGrantServer {
    /// The test key's private half (RFC 8037, appendix A.1).
    private static let key: Curve25519.Signing.PrivateKey = {
        // The literal is 32 bytes of valid base64, an Ed25519 private key, so neither step fails.
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A=")!)
        } catch {
            preconditionFailure("The example's grant key doesn't decode: \(error)")
        }
    }()

    /// A grant for a session with `app`, as a signed token.
    @MainActor
    static func grant(for app: DebugDrawerSidecarApp) throws -> String {
        let now = Date()
        return try token(for: DebugDrawerGrant(
            id: UUID().uuidString,
            subject: "tester@example.com",
            audiences: [app.bundleIdentifier],
            capabilities: app.capabilities.filter { $0 != DebugDrawerSessions.pluginID },
            notBefore: now,
            expires: now.addingTimeInterval(15 * 60)
        ))
    }

    /// `grant`, as a JWS compact token in DebugDrawer's grant format.
    private static func token(for grant: DebugDrawerGrant) throws -> String {
        struct Claims: Encodable {
            let jti: String
            let sub: String
            let aud: [String]
            let nbf: Int
            let exp: Int
            let capabilities: [String]
        }
        let header = Data(#"{"alg":"EdDSA","typ":"debugdrawer-grant+jwt"}"#.utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let claims = try encoder.encode(Claims(
            jti: grant.id, sub: grant.subject, aud: grant.audiences,
            nbf: Int(grant.notBefore.timeIntervalSince1970), exp: Int(grant.expires.timeIntervalSince1970),
            capabilities: grant.capabilities
        ))
        let signingInput = "\(base64URL(header)).\(base64URL(claims))"
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature))"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
