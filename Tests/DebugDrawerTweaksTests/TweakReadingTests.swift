#if DEBUG
    import Combine
    @testable import DebugDrawerTweaks
    import Foundation
    import Testing

    // What the app's accessors read in each build: `TweakStore.Reading.build` is `.everyTweak` in a
    // debug build and `.offeredProductionSafeTweaks` in release, and these tests pin both from a
    // debug build by making each store with the reading under test.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweakReadingTests {
        @Test("A debug build reads every tweak's stored value")
        func debugReadsEveryTweak() {
            let storage = FakeTweakStorage(["backend": .string("staging"), "verbose": .bool(true)])
            let backend = Tweak.picker("Backend", key: "backend", default: Server.production).productionSafe()
            let verbose = Tweak.toggle("Verbose logging", key: "verbose", default: false)

            let sut = TweakStore(storage: storage, reading: .everyTweak)

            let actualBackend: Server = sut.value(of: backend)
            #expect(TweakStore.Reading.build == .everyTweak)
            #expect(actualBackend == .staging)
            #expect(sut.value(of: verbose))
        }

        @Test("A release build reads every default until the tweaks capability is made, then only the production-safe tweaks' stored values")
        func releaseReadsOfferedProductionSafeTweaks() {
            let storage = FakeTweakStorage(["backend": .string("staging"), "verbose": .bool(true)])
            let backend = Tweak.picker("Backend", key: "backend", default: Server.production).productionSafe()
            let verbose = Tweak.toggle("Verbose logging", key: "verbose", default: false)
            let sut = TweakStore(storage: storage, reading: .offeredProductionSafeTweaks)
            let before: Server = sut.value(of: backend)
            let verboseBefore = sut.value(of: verbose)

            _ = TweaksModel(tweaks: [AnyTweak(backend), AnyTweak(verbose)], store: sut)

            let after: Server = sut.value(of: backend)
            #expect(before == .production)
            #expect(!verboseBefore)
            #expect(after == .staging)
            #expect(!sut.value(of: verbose))
        }

        @Test("In a release build, an offered production-safe tweak's publisher follows stored changes, and an unmarked one's sends its default")
        func releasePublishers() {
            let storage = FakeTweakStorage()
            let backend = Tweak.picker("Backend", key: "backend", default: Server.production).productionSafe()
            let verbose = Tweak.toggle("Verbose logging", key: "verbose", default: false)
            let sut = TweakStore(storage: storage, reading: .offeredProductionSafeTweaks)
            _ = TweaksModel(tweaks: [AnyTweak(backend)], store: sut)
            var backends: [Server] = []
            var verboses: [Bool] = []
            let subscriptions = [
                sut.publisher(for: backend).sink { backends.append($0) },
                sut.publisher(for: verbose).sink { verboses.append($0) }
            ]
            let expectedBackends: [Server] = [.production, .local, .production]

            sut.set(.local, for: backend)
            sut.set(true, for: verbose)
            sut.setStoredValue(nil, forKey: "backend")

            #expect(backends == expectedBackends)
            #expect(verboses == [false])
            #expect(subscriptions.count == 2)
        }
    }
#endif
