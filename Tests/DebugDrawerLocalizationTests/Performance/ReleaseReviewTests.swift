// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the review is tested compiled without DEBUG, as a production app's build is: through the
// public API, a real receiver and the command files a sidecar leaves in its store (the sidecar's
// transports are debug-build types). In debug the file is empty; LocalizationReviewReceiverTests
// covers the same through the sidecar's transport.
#if !DEBUG
    import DebugDrawerLocalization
    import DebugDrawerReceiver
    import Foundation
    import ObjectiveC
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReleaseReviewTests {
        @Test("In release, a session shows the keys of strings read through the review, replaces no lookup, and its end shows translations")
        func showsKeysForTheSession() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ReleaseReviewTests-\(UUID().uuidString)")
            let lproj = root.appending(path: "Fixture.bundle/en.lproj", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try Data(#""greeting" = "Hello";"#.utf8).write(to: lproj.appending(path: "Localizable.strings"))
            let bundle = try #require(Bundle(url: root.appending(path: "Fixture.bundle")))
            let directory = root.appending(path: "Store")
            let layout = AppGroupStoreLayout(directory: directory)
            #expect(layout.create())
            let commands: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (LocalizationReview.pluginID, TransportMessage.payload(LocalizationReview.Command.setMode(.showingKeys)))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let selector = #selector(Bundle.localizedString(forKey:value:table:))
            let method = try #require(class_getInstanceMethod(Bundle.self, selector))
            let expectedImplementation = method_getImplementation(method)
            let review = LocalizationReview()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.localizationReview(review))

            try receiver.start()
            defer { receiver.stop() }
            let during = (
                review.mode,
                review.localizedString(forKey: "greeting", bundle: bundle),
                bundle.localizedString(forKey: "greeting", value: nil, table: nil)
            )
            sessions.end()
            let after = (review.mode, review.localizedString(forKey: "greeting", bundle: bundle))

            #expect(during.0 == .showingKeys)
            #expect(during.1 == "greeting")
            #expect(during.2 == "Hello")
            #expect(method_getImplementation(method) == expectedImplementation)
            #expect(after.0 == .standard)
            #expect(after.1 == "Hello")
        }
    }
#endif
