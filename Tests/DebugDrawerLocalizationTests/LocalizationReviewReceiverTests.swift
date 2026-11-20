// The localization review as a sidecar reaches it: a real DebugDrawerReceiver serving the app-group
// store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) reading it from
// the same directory, opening and ending sessions through the sessions' own model. Each test makes
// a review of its own, so tests running at once don't share a mode, and looks its strings up in a
// bundle it writes to a folder of its own.
#if DEBUG
    import Combine
    import DebugDrawer
    import DebugDrawerLocalization
    import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A model the test enables beside nothing else, so a session can open in a receiver whose
    /// localization review isn't enabled.
    @MainActor
    private final class CounterModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
        }

        enum Command: Codable, Sendable {
            case increment
            case reset
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case .increment: snapshot.count += 1
            case .reset: snapshot.count = 0
            }
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocalizationReviewReceiverTests {
        /// A bundle of its own, in a new folder, whose English `Localizable.strings` translates
        /// `greeting` as "Hello".
        private func fixtureBundle() throws -> Bundle {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "LocalizationReviewReceiverTests-\(UUID().uuidString)/Fixture.bundle", directoryHint: .isDirectory)
            let lproj = url.appending(path: "en.lproj", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try Data(#""greeting" = "Hello";"#.utf8).write(to: lproj.appending(path: "Localizable.strings"))
            let info: [String: Any] = ["CFBundleIdentifier": "debugdrawer.tests.review.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appending(path: "Info.plist"))
            return try #require(Bundle(url: url))
        }

        @Test("Inside a session a sidecar shows the keys, then pseudo-localized text, and the session's end shows the translations again")
        func togglesWithinSessionAndRevertsAtEnd() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocalizationReviewReceiverTests-\(UUID().uuidString)")
            let bundle = try fixtureBundle()
            let review = LocalizationReview()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.localizationReview(review))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let modes = try await sidecar.connect(
                toPlugin: LocalizationReview.pluginID, snapshot: LocalizationReview.Snapshot.self, command: LocalizationReview.Command.self
            )
            var published = modes.snapshots().makeAsyncIterator()
            var sessionStates = sessionControl.snapshots().makeAsyncIterator()
            func lookUp() -> String {
                review.localizedString(forKey: "greeting", bundle: bundle)
            }
            let expectedTranslation = "Hello"
            let expectedKey = "greeting"
            let expectedPseudo = "[Ĥéļļö··]"

            let before = lookUp()
            sessionControl.send(.open(duration: 60))
            while let state = await sessionStates.next(), !state.isActive {}
            modes.send(.setMode(.showingKeys))
            var showingKeys: LocalizationReview.Snapshot?
            while let snapshot = await published.next() {
                if snapshot.mode == .showingKeys {
                    showingKeys = snapshot
                    break
                }
            }
            let keyed = lookUp()
            modes.send(.setMode(.pseudoLocalized))
            var pseudoLocalized: LocalizationReview.Snapshot?
            while let snapshot = await published.next() {
                if snapshot.mode == .pseudoLocalized {
                    pseudoLocalized = snapshot
                    break
                }
            }
            let pseudo = lookUp()
            sessionControl.send(.end)
            var reverted: LocalizationReview.Snapshot?
            while let snapshot = await published.next() {
                if snapshot.mode == .standard {
                    reverted = snapshot
                    break
                }
            }
            let after = lookUp()

            #expect(before == expectedTranslation)
            #expect(showingKeys == LocalizationReview.Snapshot(mode: .showingKeys))
            #expect(keyed == expectedKey)
            #expect(pseudoLocalized == LocalizationReview.Snapshot(mode: .pseudoLocalized))
            #expect(pseudo == expectedPseudo)
            #expect(reverted == LocalizationReview.Snapshot(mode: .standard))
            #expect(review.mode == .standard)
            #expect(after == expectedTranslation)
            #expect(sessions.auditLog.filter { $0.capability == LocalizationReview.pluginID }.map(\.event) == [
                .commandApplied, .commandApplied, .changeReverted
            ])
        }

        @Test("Outside a session a sidecar's mode is refused, and every string shows its translation")
        func refusedOutsideSession() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocalizationReviewReceiverTests-\(UUID().uuidString)")
            let bundle = try fixtureBundle()
            let review = LocalizationReview()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.localizationReview(review))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let modes = try await sidecar.connect(
                toPlugin: LocalizationReview.pluginID, snapshot: LocalizationReview.Snapshot.self, command: LocalizationReview.Command.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            let expected = DebugDrawerAuditEntry.Event.commandRefused(.noActiveSession)

            modes.send(.setMode(.showingKeys))
            var refusal: DebugDrawerAuditEntry?
            for await entry in arrivals where entry.capability == LocalizationReview.pluginID {
                refusal = entry
                break
            }

            #expect(refusal?.event == expected)
            #expect(review.mode == .standard)
            #expect(review.snapshot == LocalizationReview.Snapshot(mode: .standard))
            #expect(review.localizedString(forKey: "greeting", bundle: bundle) == "Hello")
        }

        @Test("In a session of a receiver that didn't enable the review, a sidecar's mode is refused as an unknown capability")
        func refusedWhenNotEnabled() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "LocalizationReviewReceiverTests-\(UUID().uuidString)")
            let bundle = try fixtureBundle()
            let review = LocalizationReview()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.model(CounterModel(), id: "Tests.Counter", scope: .session(revertWith: .reset)))
            // The commands a sidecar's transport would leave, as files in the store: the transport
            // can't connect to a capability the app doesn't serve, since no snapshot of it is
            // written. The receiver performs them in name order as it starts.
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let commands: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (LocalizationReview.pluginID, TransportMessage.payload(LocalizationReview.Command.setMode(.pseudoLocalized)))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let expected = DebugDrawerAuditEntry.Event.commandRefused(.unknownCapability)

            try receiver.start()
            defer { receiver.stop() }
            let refusal = sessions.auditLog.last

            #expect(sessions.snapshot.isActive)
            #expect(refusal?.capability == LocalizationReview.pluginID)
            #expect(refusal?.event == expected)
            #expect(review.mode == .standard)
            #expect(review.localizedString(forKey: "greeting", bundle: bundle) == "Hello")
            #expect(receiver.enabledCapabilities == ["Tests.Counter"])
        }
    }
#endif
