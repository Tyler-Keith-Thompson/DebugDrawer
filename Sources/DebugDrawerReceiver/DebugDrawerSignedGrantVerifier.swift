import Foundation

// DebugDrawer's own grant format is a JSON Web Token in the JWS compact serialization (RFC 7515,
// RFC 7519), signed with EdDSA over Ed25519 (RFC 8037) or ES256, so a company's server issues one
// with whatever JWT library it already has. The usual JWT pitfalls are closed off here: the
// algorithm comes from the key the app trusts, never from the token alone (no "none", no
// switching a key to another algorithm); the header must name the grant's own type, so no other
// token the same key signs (an SSO ID token, say) passes as a grant; a header with "crit" is
// refused, as this verifier understands no extension; the signature is checked before the claims
// are read; and a token longer than `maximumTokenLength` isn't parsed at all. Rejected: a format
// of DebugDrawer's own (every server team would hand-write it), COSE/CBOR (no Apple framework
// reads it) and PASETO (fewer server libraries, Ed25519 only).

/// Verifies grants in DebugDrawer's format: a JSON Web Token signed by a key the app embeds.
///
/// A grant is three base64url segments (no padding) joined by `.`: a header, the claims and the
/// signature. The header is `{"alg":"EdDSA","typ":"debugdrawer-grant+jwt"}` for an Ed25519 key or
/// `{"alg":"ES256","typ":"debugdrawer-grant+jwt"}` for a P-256 key. The claims are `jti` (the
/// grant's ID), `sub` (who holds it), `aud` (the app's bundle identifier, or an array of them),
/// `nbf` and `exp` (seconds since 1970) and `capabilities` (an array of capability IDs). The
/// signature is over the ASCII bytes of the header and claims segments joined by `.`: 64 bytes,
/// Ed25519's, or ES256's `r` and `s`. The README's "Signed grants" section shows a signer.
public struct DebugDrawerSignedGrantVerifier: DebugDrawerGrantVerifier {
    /// The `typ` a grant's header must name.
    public static let tokenType = "debugdrawer-grant+jwt"
    /// The longest token, in bytes, the verifier reads; a longer one is malformed.
    public static let maximumTokenLength = 8192

    /// The keys a grant may be signed with; each verifies only the algorithm it is for.
    public let keys: [DebugDrawerGrantPublicKey]

    /// A verifier trusting `keys`: list more than one while the server rotates its key.
    ///
    /// - Parameter keys: The grant server's public keys.
    public init(keys: [DebugDrawerGrantPublicKey]) {
        self.keys = keys
    }

    /// The grant `token` carries, once a trusted key's signature over it is checked.
    ///
    /// - Parameter token: A grant in DebugDrawer's format.
    /// - Returns: What the grant allows.
    /// - Throws: ``DebugDrawerGrantVerificationError/malformed`` for a token that isn't three
    ///   base64url segments, whose header isn't a grant's, or whose claims are missing a field;
    ///   ``DebugDrawerGrantVerificationError/invalidSignature`` when no key for the header's
    ///   algorithm signed it.
    public func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
        guard token.utf8.count <= Self.maximumTokenLength else { throw .malformed }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let headerData = Data(base64URLEncoded: segments[0]),
              let claimsData = Data(base64URLEncoded: segments[1]),
              let signature = Data(base64URLEncoded: segments[2]),
              let header = try? JSONDecoder().decode(GrantHeader.self, from: headerData),
              header.typ == Self.tokenType, header.crit == nil
        else { throw .malformed }
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        guard keys.contains(where: { $0.algorithm == header.alg && $0.isValidSignature(signature, for: signingInput) }) else {
            throw .invalidSignature
        }
        guard let claims = try? JSONDecoder().decode(GrantClaims.self, from: claimsData), !claims.jti.isEmpty else { throw .malformed }
        return DebugDrawerGrant(
            id: claims.jti,
            subject: claims.sub,
            audiences: claims.aud,
            capabilities: claims.capabilities,
            notBefore: Date(timeIntervalSince1970: claims.nbf),
            expires: Date(timeIntervalSince1970: claims.exp)
        )
    }
}

/// A grant's JOSE header: the members this verifier reads.
private struct GrantHeader: Decodable {
    let alg: String
    let typ: String
    /// Present only in a token that needs an extension this verifier doesn't understand.
    let crit: [String]?
}

/// A grant's claims.
private struct GrantClaims: Decodable {
    let jti: String
    let sub: String
    let aud: [String]
    let nbf: TimeInterval
    let exp: TimeInterval
    let capabilities: [String]

    private enum CodingKeys: String, CodingKey {
        case jti, sub, aud, nbf, exp, capabilities
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jti = try container.decode(String.self, forKey: .jti)
        sub = try container.decode(String.self, forKey: .sub)
        // RFC 7519 allows a single audience as a string, or an array of them.
        if let audience = try? container.decode(String.self, forKey: .aud) {
            aud = [audience]
        } else {
            aud = try container.decode([String].self, forKey: .aud)
        }
        nbf = try container.decode(TimeInterval.self, forKey: .nbf)
        exp = try container.decode(TimeInterval.self, forKey: .exp)
        capabilities = try container.decode([String].self, forKey: .capabilities)
    }
}

extension Data {
    /// The bytes `text` encodes in base64url without padding (RFC 4648 §5), or `nil` when it has
    /// any other character or isn't the bytes' one encoding.
    fileprivate init?(base64URLEncoded text: Substring) {
        guard text.utf8.allSatisfy({ $0.isBase64URLDigit }) else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        // Foundation ignores the unused low bits of a segment's last digit, so two spellings
        // would decode to the same bytes; only the canonical one is a grant's.
        guard let data = Data(base64Encoded: standard), data.base64EncodedString() == standard else { return nil }
        self = data
    }
}

extension UInt8 {
    /// Whether this ASCII byte is one of base64url's 64 digits.
    fileprivate var isBase64URLDigit: Bool {
        switch self {
        case UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "0") ... UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "_"):
            true
        default:
            false
        }
    }
}
