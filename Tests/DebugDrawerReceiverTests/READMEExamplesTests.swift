// The README's "Signed grants" examples, verbatim, so the README cannot drift from the code. The
// test signer is the README's too: the grant tests in this target sign with it, so the format
// the README documents is the one they prove.
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

#if DEBUG
    import DebugDrawer
    import Testing

    // The README's flag adapter, from "Production builds: the receiver", which the grant example
    // enables.
    @MainActor
    final class FlagServiceAdapter: DebugDrawerFeatureFlagAdapter {
        private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

        func overridableFlags() -> [DebugDrawerFeatureFlag] {
            [DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false))]
        }

        func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
            overrides[key] = value
        }

        func clearOverride(forKey key: String) {
            overrides[key] = nil
        }
    }

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

    @MainActor
    @Suite("README examples", .timeLimit(.minutes(1)))
    struct READMEExamplesTests {
        @Test("Signed grants: a session opens with a grant the test signer issued, and the flag it covers is overridden")
        func signedGrants() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEGrants-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let flags = FlagServiceAdapter()
            let app = try GrantedProductionReceiver(flags: flags, grantServerKey: serverKey.publicKey, container: container)
            defer { app.receiver.stop() }
            let grantFromServer = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: UUID().uuidString, subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [DebugDrawerFeatureFlagOverrides.pluginID],
                notBefore: Date(), expires: Date().addingTimeInterval(10 * 60)
            ))
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = app.sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()
            let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]

            // In the sidecar, once the employee signed in and the company's server issued a grant:
            sessionControl.send(.open(duration: 15 * 60, grant: grantFromServer))
            let opened = await recorded.next()
            // The flags are served once the session, whose grant lists them, is open.
            let flagControl = try await sidecar.connect(
                toPlugin: DebugDrawerFeatureFlagOverrides.pluginID,
                snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self,
                command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            flagControl.send(.setOverride(key: "new-checkout", value: .bool(true)))
            let applied = await recorded.next()

            #expect(opened?.event == .sessionOpened(
                expires: try #require(app.sessions.snapshot.session?.expires),
                grant: .init(id: try #require(app.sessions.snapshot.session?.grant?.id), subject: "jane@example.com")
            ))
            #expect(applied?.event == .commandApplied)
            #expect(flags.overrides == expectedOverrides)
        }
    }
#endif
