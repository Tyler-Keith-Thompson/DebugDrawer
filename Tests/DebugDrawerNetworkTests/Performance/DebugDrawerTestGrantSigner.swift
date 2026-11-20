// The README's test signer ("Signed grants"), copied: network mocking needs a grant in every
// receiver, so the release tests open each session with one it signs.
import CryptoKit
import DebugDrawerReceiver
import Foundation

/// Signs grants in DebugDrawer's format with an Ed25519 key: for tests, and as a reference for
/// the server that issues them.
struct DebugDrawerTestGrantSigner {
    let key: Curve25519.Signing.PrivateKey

    func token(for grant: DebugDrawerGrant) throws -> String {
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

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
