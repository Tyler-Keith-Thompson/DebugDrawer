# Signed Grants: Who May Open a Session

Require a short-lived grant from your company's server before a sidecar can open a session, and
limit the session to the capabilities the grant lists.

## Overview

Team signing and a shared app group keep other companies' apps out, but not a sidecar build that
reached the wrong person, and a macOS group container is weaker than an iOS one
(<doc:SecurityModel>). Grants are an optional layer on top. The sidecar signs the employee in (with
the company's SSO, which the sidecar implements) and gets a short-lived grant from the company's
server, listing the capabilities that person may drive and when it expires. The app verifies it
with a public key it embeds. Without a grant policy, sessions work exactly as
<doc:ProductionBuilds> describes.

```swift
import CryptoKit
import DebugDrawerReceiver

@MainActor
final class GrantedProductionReceiver {
    let sessions: DebugDrawerSessions
    let receiver: DebugDrawerReceiver

    init(flags: FlagServiceAdapter, grantServerKey: Curve25519.Signing.PublicKey, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        try receiver.start()
    }
}
```

The sidecar sends the grant once, as it opens the session:

```swift
// In the sidecar, once the employee signed in and the company's server issued a grant:
sessionControl.send(.open(duration: 15 * 60, grant: grantFromServer))
```

### Default-deny with a policy

With a policy, the sessions are default-deny.

A session needs a valid grant. Opening one is refused as:

- `commandRefused(.grantMissing)` without a grant;
- `.grantInvalid` with one the verifier rejects (malformed, or not signed by a trusted key as it
  is);
- `.grantWrongAudience` with one issued for another app (its `aud` lacks the policy's `audience`);
- `.grantNotYetValid` before its `nbf`;
- `.grantExpired` at or after its `exp`;
- `.grantReplayed` with one that already opened a session.

Each refusal is audited, and every command after it is refused as `.noActiveSession`.

The grant bounds the session. A session expires at its `exp` at the latest, whatever duration the
sidecar asked for, and a command in it to a capability the grant doesn't list is refused as
`.capabilityNotGranted`. `session.grant` holds the grant (`id`, `subject`, `audiences`,
`capabilities`, `notBefore`, `expires`), so the app's indicator can show who holds it.

### Clock skew

A grant is accepted up to `clockSkewTolerance` seconds (a minute by default) before its `nbf`, for
a server whose clock runs ahead of the device's. `exp` is never extended.

### One session per grant

The app remembers the grant IDs it accepted until each expires, in memory. After a relaunch, a grant
copied from the store could open one more session before it expires, so issue grants that last
minutes, not days.

### Nothing secret is kept

The token and its signature are read once and never written to a snapshot or the audit log.
`sessionOpened(expires:grant:)` names the grant by its `id` and `subject` alone.

### High-risk capabilities

`.requiringGrant()` on a capability
(`receiver.enable(.model(environments, id: "MyApp.Environment", scope: .session(revertWith: .reset)).requiringGrant())`)
refuses its commands as `.grantMissing` in a session without a grant, so the capability works only
in an app that configures grants.

### The grant format

A grant is a JSON Web Token (RFC 7519) in JWS compact serialization (RFC 7515), so a server issues
one with any JWT library. It is three base64url segments without padding, each the canonical
encoding of its bytes, joined by `.`.

The header is `{"alg":"EdDSA","typ":"debugdrawer-grant+jwt"}` for an Ed25519 key (RFC 8037), or
`{"alg":"ES256","typ":"debugdrawer-grant+jwt"}` for a P-256 key. `typ` must be exactly that, so no
other token the key signs passes as a grant, and a header with `crit` is refused. The app trusts the
keys it lists, each for its own algorithm (`.ed25519(_:)`, `.p256(_:)`); list two while the server
rotates its key.

The claims are:

- `jti`, the grant's unique ID, a non-empty string;
- `sub`, who holds it;
- `aud`, the app's bundle identifier, as a string or an array of them;
- `nbf` and `exp`, seconds since 1970, as numbers;
- `capabilities`, an array of the capability IDs it allows, such as
  `"DebugDrawer.FeatureFlagOverrides"`.

Other claims are ignored.

The signature is over the ASCII bytes of `<header segment>.<claims segment>`: Ed25519's 64-byte
signature, or ES256's 64-byte `r` and `s` (ECDSA over SHA-256). It is checked before the claims are
read, and a token over 8,192 bytes isn't read at all.

### A test signer

The repository's tests sign every grant with this test signer, which shows each step:

```swift
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
```

For example, the test signer with RFC 8037's Ed25519 key (public key
`11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo` in base64url) issued this grant for
`DebugDrawer.FeatureFlagOverrides` to `jane@example.com`, for `com.example.MyApp`, from 1778307200
to 1778308100. Its claims segment decodes to
`{"aud":["com.example.MyApp"],"capabilities":["DebugDrawer.FeatureFlagOverrides"],"exp":1778308100,"jti":"grant-0001","nbf":1778307200,"sub":"jane@example.com"}`:

```
eyJhbGciOiJFZERTQSIsInR5cCI6ImRlYnVnZHJhd2VyLWdyYW50K2p3dCJ9.eyJhdWQiOlsiY29tLmV4YW1wbGUuTXlBcHAiXSwiY2FwYWJpbGl0aWVzIjpbIkRlYnVnRHJhd2VyLkZlYXR1cmVGbGFnT3ZlcnJpZGVzIl0sImV4cCI6MTc3ODMwODEwMCwianRpIjoiZ3JhbnQtMDAwMSIsIm5iZiI6MTc3ODMwNzIwMCwic3ViIjoiamFuZUBleGFtcGxlLmNvbSJ9.Cc_FvvFlgJZkYRx3JqfE6EtZY4A8GF30qbGB5gLa51q7PN3a52hwmmLAYLBURiZrQ1NuoCFJUp_c89PJC5bFCA
```

Ed25519 in CryptoKit randomizes its signatures, so signing the same claims again gives another
signature that verifies just as well. Keep the private key on the server; the app holds only the
public key.

### Other token formats

To accept another format (a token your SSO already issues, say), conform to
`DebugDrawerGrantVerifier`: check the signature and return a `DebugDrawerGrant`. The sessions then
check the audience, validity window, single use and capabilities as described above.
