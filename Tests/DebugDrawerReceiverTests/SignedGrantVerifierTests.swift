import CryptoKit
@testable import DebugDrawerReceiver
import Foundation
import Testing

// The built-in verifier on its own: what it accepts and what it rejects, before any policy. The
// golden grants were signed once with RFC 8037 A.1's Ed25519 key: the first by the README's
// `DebugDrawerTestGrantSigner`, the second, whose `aud` is a single string as RFC 7519 allows, by
// an earlier draft of it. CryptoKit randomizes Ed25519 signatures, so the tokens are pinned rather
// than signed again here.
@Suite
struct SignedGrantVerifierTests {
    /// RFC 8037 A.1's Ed25519 public key, x.
    private static let goldenPublicKey = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
    /// A grant for DebugDrawer.FeatureFlagOverrides, issued to jane@example.com for
    /// com.example.MyApp, valid from 1778307200 to 1778308100 (seconds since 1970).
    private static let goldenGrant = "eyJhbGciOiJFZERTQSIsInR5cCI6ImRlYnVnZHJhd2VyLWdyYW50K2p3dCJ9"
        + ".eyJhdWQiOlsiY29tLmV4YW1wbGUuTXlBcHAiXSwiY2FwYWJpbGl0aWVzIjpbIkRlYnVnRHJhd2VyLkZlYXR1cmVGbGFnT3ZlcnJpZGVzIl0sImV4cCI6MTc3"
        + "ODMwODEwMCwianRpIjoiZ3JhbnQtMDAwMSIsIm5iZiI6MTc3ODMwNzIwMCwic3ViIjoiamFuZUBleGFtcGxlLmNvbSJ9"
        + ".Cc_FvvFlgJZkYRx3JqfE6EtZY4A8GF30qbGB5gLa51q7PN3a52hwmmLAYLBURiZrQ1NuoCFJUp_c89PJC5bFCA"
    /// The same grant with `"aud":"com.example.MyApp"`.
    private static let goldenGrantSingleAudience = "eyJhbGciOiJFZERTQSIsInR5cCI6ImRlYnVnZHJhd2VyLWdyYW50K2p3dCJ9"
        + ".eyJhdWQiOiJjb20uZXhhbXBsZS5NeUFwcCIsImNhcGFiaWxpdGllcyI6WyJEZWJ1Z0RyYXdlci5GZWF0dXJlRmxhZ092ZXJyaWRlcyJdLCJleHAiOjE3Nzgz"
        + "MDgxMDAsImp0aSI6ImdyYW50LTAwMDEiLCJuYmYiOjE3NzgzMDcyMDAsInN1YiI6ImphbmVAZXhhbXBsZS5jb20ifQ"
        + ".OeEJcUfyQmV1Wt9S_dwrp0hHSiLhbktqmWKGD24g_EU_BnWIjXuUuFMhO_iqo6NrMWUgCPJzYVYMbFagtsJiBQ"

    @Test("Each golden grant, verified with its fixed public key, gives exactly its claims")
    func goldenGrants() throws {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64Encoded: Self.goldenPublicKey)))
        let sut = DebugDrawerSignedGrantVerifier(keys: [.ed25519(key)])
        let expected = DebugDrawerGrant(
            id: "grant-0001",
            subject: "jane@example.com",
            audiences: ["com.example.MyApp"],
            capabilities: ["DebugDrawer.FeatureFlagOverrides"],
            notBefore: Date(timeIntervalSince1970: 1_778_307_200),
            expires: Date(timeIntervalSince1970: 1_778_308_100)
        )

        let actual = try [Self.goldenGrant, Self.goldenGrantSingleAudience].map { try sut.verify($0) }

        #expect(actual == [expected, expected])
    }

    @Test("The golden grant with any one character of its claims or signature changed fails its signature or is malformed")
    func goldenGrantTampered() throws {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64Encoded: Self.goldenPublicKey)))
        let sut = DebugDrawerSignedGrantVerifier(keys: [.ed25519(key)])
        let headerLength = Self.goldenGrant.split(separator: ".")[0].count
        let characters = Array(Self.goldenGrant)
        var outcomes: [DebugDrawerGrantVerificationError] = []

        for index in characters.indices where index > headerLength && characters[index] != "." {
            var tampered = characters
            tampered[index] = characters[index] == "A" ? "B" : "A"
            do {
                _ = try sut.verify(String(tampered))
                Issue.record("A grant changed at \(index) verified")
            } catch {
                outcomes.append(error)
            }
        }

        #expect(outcomes.count == characters.count - headerLength - 2)
        #expect(outcomes.allSatisfy { $0 == .invalidSignature || $0 == .malformed })
        #expect(outcomes.contains(.invalidSignature))
    }

    @Test("A grant signed by a key the verifier doesn't trust fails its signature")
    func untrustedKey() throws {
        let trusted = Curve25519.Signing.PrivateKey()
        let other = Curve25519.Signing.PrivateKey()
        let token = try DebugDrawerTestGrantSigner(key: other).token(for: DebugDrawerGrant(
            id: "g", subject: "jane@example.com", audiences: ["com.example.MyApp"],
            capabilities: ["A"],
            notBefore: Date(timeIntervalSince1970: 1_778_307_200), expires: Date(timeIntervalSince1970: 1_778_308_100)
        ))
        let sut = DebugDrawerSignedGrantVerifier(keys: [.ed25519(trusted.publicKey)])

        #expect(throws: DebugDrawerGrantVerificationError.invalidSignature) {
            try sut.verify(token)
        }
    }

    @Test("Of several trusted keys, the one that signed the grant verifies it, so a server can rotate its key")
    func rotatedKeys() throws {
        let retired = Curve25519.Signing.PrivateKey()
        let current = Curve25519.Signing.PrivateKey()
        let token = try DebugDrawerTestGrantSigner(key: current).token(for: DebugDrawerGrant(
            id: "g", subject: "jane@example.com", audiences: ["com.example.MyApp"],
            capabilities: ["A"],
            notBefore: Date(timeIntervalSince1970: 1_778_307_200), expires: Date(timeIntervalSince1970: 1_778_308_100)
        ))
        let sut = DebugDrawerSignedGrantVerifier(keys: [.ed25519(retired.publicKey), .ed25519(current.publicKey)])

        let actual = try sut.verify(token)

        #expect(actual.id == "g")
    }

    @Test("An ES256 grant verifies with its P-256 key, and fails with an Ed25519 key or once its claims change")
    func p256() throws {
        let key = P256.Signing.PrivateKey()
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"ES256","typ":"debugdrawer-grant+jwt"}"#.utf8))
        let claimsJSON = #"{"jti":"p","sub":"sam@example.com","aud":["com.example.MyApp","com.example.Other"],"nbf":1778307200.5,"#
            + #""exp":1778308100,"capabilities":["A","B"]}"#
        let claims = base64URL(Data(claimsJSON.utf8))
        let otherClaims = base64URL(Data(
            #"{"jti":"p","sub":"sam@example.com","aud":"com.example.MyApp","nbf":1778307200,"exp":1878308100,"capabilities":["A","B"]}"#.utf8
        ))
        let signature = try base64URL(key.signature(for: Data("\(header).\(claims)".utf8)).rawRepresentation)
        let sut = DebugDrawerSignedGrantVerifier(keys: [.p256(key.publicKey)])
        let wrongAlgorithm = DebugDrawerSignedGrantVerifier(keys: [.ed25519(Curve25519.Signing.PrivateKey().publicKey)])
        let expected = DebugDrawerGrant(
            id: "p",
            subject: "sam@example.com",
            audiences: ["com.example.MyApp", "com.example.Other"],
            capabilities: ["A", "B"],
            notBefore: Date(timeIntervalSince1970: 1_778_307_200.5),
            expires: Date(timeIntervalSince1970: 1_778_308_100)
        )

        let actual = try sut.verify("\(header).\(claims).\(signature)")

        #expect(actual == expected)
        #expect(throws: DebugDrawerGrantVerificationError.invalidSignature) {
            try wrongAlgorithm.verify("\(header).\(claims).\(signature)")
        }
        #expect(throws: DebugDrawerGrantVerificationError.invalidSignature) {
            try sut.verify("\(header).\(otherClaims).\(signature)")
        }
    }

    @Test(
        "A token that isn't a signed grant's three segments, header and claims is malformed or fails its signature",
        arguments: [
            ("", DebugDrawerGrantVerificationError.malformed),
            ("not-a-grant", .malformed),
            ("a.b", .malformed),
            ("a.b.c.d", .malformed),
            // A JWS from RFC 8037 A.4: a real Ed25519 signature, but no grant's typ.
            (
                "eyJhbGciOiJFZERTQSJ9.RXhhbXBsZSBvZiBFZDI1NTE5IHNpZ25pbmc"
                    + ".hgyY0il_MGCjP0JzlnLWG1PPOt7-09PGcvMg3AIbQR6dWbhijcNR4ki4iylGjg5BhVsPt9g7sVvpAr_MuM0KAg",
                .malformed
            ),
            // {"alg":"none","typ":"debugdrawer-grant+jwt"}, unsigned.
            ("eyJhbGciOiJub25lIiwidHlwIjoiZGVidWdkcmF3ZXItZ3JhbnQrand0In0.e30.", .invalidSignature),
            // {"alg":"EdDSA","typ":"debugdrawer-grant+jwt","crit":["exp"]}
            ("eyJhbGciOiJFZERTQSIsInR5cCI6ImRlYnVnZHJhd2VyLWdyYW50K2p3dCIsImNyaXQiOlsiZXhwIl19.e30.AA", .malformed),
            // Padded base64 is not base64url.
            ("eyJhbGciOiJFZERTQSIsInR5cCI6ImRlYnVnZHJhd2VyLWdyYW50K2p3dCJ9==.e30.AA", .malformed),
            (String(repeating: "A", count: DebugDrawerSignedGrantVerifier.maximumTokenLength + 1), .malformed)
        ]
    )
    func malformed(token: String, expected: DebugDrawerGrantVerificationError) throws {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64Encoded: Self.goldenPublicKey)))
        let sut = DebugDrawerSignedGrantVerifier(keys: [.ed25519(key)])

        #expect(throws: expected) {
            try sut.verify(token)
        }
    }

    @Test("A correctly signed grant missing a claim is malformed")
    func missingClaim() throws {
        let key = Curve25519.Signing.PrivateKey()
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"EdDSA","typ":"debugdrawer-grant+jwt"}"#.utf8))
        let claims = base64URL(Data(#"{"jti":"g","sub":"jane@example.com","aud":"com.example.MyApp","nbf":1778307200,"exp":1778308100}"#.utf8))
        let signature = try base64URL(key.signature(for: Data("\(header).\(claims)".utf8)))
        let sut = DebugDrawerSignedGrantVerifier(keys: [.ed25519(key.publicKey)])

        #expect(throws: DebugDrawerGrantVerificationError.malformed) {
            try sut.verify("\(header).\(claims).\(signature)")
        }
    }
}
