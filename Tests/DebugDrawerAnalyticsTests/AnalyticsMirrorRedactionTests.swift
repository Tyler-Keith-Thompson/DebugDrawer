// Redaction end to end: events recorded through the sink while a sidecar's session is open, read by
// the sidecar's store transport from a real receiver, then every byte the receiver left on disk,
// the snapshot's JSON and the audit log searched for each secret. A store file holds its message's
// payload as base64, so each file is searched as written and with that payload decoded. The secrets
// are distinct strings found nowhere else, so finding one anywhere means it leaked.
#if DEBUG
    import DebugDrawer
    import DebugDrawerAnalytics
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct AnalyticsMirrorRedactionTests {
        @Test("The default rules and a host's own mask every secret before it reaches the sidecar, the snapshot or any file")
        func secretsNeverLeave() async throws {
            let prefix = "redaction-\(UUID().uuidString)-"
            let directory = FileManager.default.temporaryDirectory.appending(path: "AnalyticsMirrorRedactionTests-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let redaction = AnalyticsRedaction.standard.adding(keys: ["customer_name"], values: [#"\bACCT-\d{6}\b"#])
            receiver.enable(.analyticsEvents(sessions: sessions, redaction: redaction))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: directory)
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let events = try await sidecar.connect(
                toPlugin: AnalyticsEventsMirror.pluginID, snapshot: AnalyticsEventsMirror.Snapshot.self, command: AnalyticsEventsMirror.Command.self
            )
            var arrivals = events.snapshots().makeAsyncIterator()
            let emailUnderKey = "dd124.key.owner@example.com"
            let emailInText = "dd124.text.owner@example.org"
            let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJkZDEyNCJ9.c2VjcmV0LXNpZ25hdHVyZS1kZDEyNA"
            let password = "hunter2-dd124-password"
            let customerName = "Ada Dd124-Lovelace"
            let account = "ACCT-124124"
            let phone = "+64 21 555 0124"
            let secrets = [emailUnderKey, emailInText, jwt, password, customerName, account, phone]
            let mask = AnalyticsValue.string(AnalyticsRedaction.mask)
            let expectedProperties: [String: AnalyticsValue] = [
                "plan": "pro",
                "seats": 3,
                "user_email": mask,
                "Phone": mask,
                "note": mask,
                "customer_name": mask,
                "reference": mask,
                "nested": ["profile": ["password": mask], "tags": ["ok", mask]],
                "label": "no secrets here"
            ]

            sessionControl.send(.open(duration: 60))
            while let snapshot = await arrivals.next(), snapshot.sessionID == nil {}
            AnalyticsEvents.record("\(prefix)signed_up", properties: [
                "plan": "pro",
                "seats": 3,
                "user_email": .string(emailUnderKey),
                "Phone": .string(phone),
                "note": .string("contact \(emailInText) later"),
                "customer_name": .string(customerName),
                "reference": .string("order for \(account)"),
                "nested": ["profile": ["password": .string(password)], "tags": ["ok", .string(jwt)]],
                "label": "no secrets here"
            ], source: "Segment")
            AnalyticsEvents.record("\(prefix)\(account)")
            var received: AnalyticsEventsMirror.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.events.count(where: { $0.name.hasPrefix(prefix) || $0.name == AnalyticsRedaction.mask }) >= 2 {
                    received = snapshot
                    break
                }
            }
            let actual = try #require(received)
            let snapshotJSON = try #require(String(bytes: JSONEncoder().encode(actual), encoding: .utf8))
            let auditJSON = try #require(String(bytes: JSONEncoder().encode(sessions.auditLog), encoding: .utf8))
            var bytesOnDisk = Data()
            let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
            while let file = files?.nextObject() as? URL {
                let bytes = (try? Data(contentsOf: file)) ?? Data()
                bytesOnDisk.append(bytes)
                if let document = StoreDocument.decoded(from: bytes) {
                    bytesOnDisk.append(document.message.payload)
                }
            }
            let noSecretsHere = Data("no secrets here".utf8)
            let signedUp = actual.events.first { $0.name == "\(prefix)signed_up" }

            #expect(signedUp?.properties == expectedProperties)
            #expect(signedUp?.source == "Segment")
            #expect(actual.events.contains { $0.name == AnalyticsRedaction.mask })
            #expect(!bytesOnDisk.isEmpty)
            #expect(bytesOnDisk.range(of: noSecretsHere) != nil)
            for secret in secrets {
                #expect(!snapshotJSON.contains(secret), "\(secret) in the sidecar's snapshot")
                #expect(!auditJSON.contains(secret), "\(secret) in the audit log")
                #expect(bytesOnDisk.range(of: Data(secret.utf8)) == nil, "\(secret) in a file in the store")
            }
        }
    }
#endif
