#if DEBUG
    import Foundation
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import Security
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStatePlanTests {
        @Test("UserDefaults lists every key of the app's domain and its app groups', less DebugDrawer's own unless they are included")
        func defaults() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let expectedKept = [
                DefaultsDomain(name: SeededAppState.appDomain, keys: ["counter", "onboarded"]),
                DefaultsDomain(name: SeededAppState.groupDomain, keys: ["shared"])
            ]
            let expectedIncluded = [
                DefaultsDomain(name: SeededAppState.appDomain, keys: ["com.debugdrawer.layout", "counter", "onboarded"]),
                DefaultsDomain(name: SeededAppState.groupDomain, keys: ["shared"])
            ]

            let kept = await seeded.appState.plan(includingDebugDrawer: false)
            let included = await seeded.appState.plan(includingDebugDrawer: true)

            #expect(kept.defaults == expectedKept)
            #expect(kept.summary(of: .userDefaults) == "3 keys")
            #expect(kept.lines(of: .userDefaults).map(\.text) == ["counter", "onboarded", "shared"])
            #expect(kept.lines(of: .userDefaults).map(\.detail) == [SeededAppState.appDomain, SeededAppState.appDomain, SeededAppState.groupDomain])
            #expect(included.defaults == expectedIncluded)
        }

        @Test("DebugDrawer's own defaults suite is listed only when DebugDrawer's settings are included")
        func debugDrawerSuite() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let suite = "com.example.app.debugdrawer"
            seeded.preferences.domains[suite] = ["com.debugdrawer.collapsed.MyApp.CachePlugin", "com.debugdrawer.hud"]
            var sut = seeded.appState
            sut.debugDrawerDomain = suite
            let expectedIncluded = DefaultsDomain(name: suite, keys: ["com.debugdrawer.collapsed.MyApp.CachePlugin", "com.debugdrawer.hud"])

            let kept = await sut.plan(includingDebugDrawer: false)
            let included = await sut.plan(includingDebugDrawer: true)

            #expect(!kept.defaults.contains { $0.name == suite })
            #expect(included.defaults.last == expectedIncluded)
        }

        @Test("A domain with nothing to remove is left out, and one key reads in the singular")
        func defaultsSingular() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            seeded.preferences.domains = [SeededAppState.appDomain: ["onboarded"], SeededAppState.groupDomain: []]

            let actual = await seeded.appState.plan(includingDebugDrawer: false)

            #expect(actual.defaults == [DefaultsDomain(name: SeededAppState.appDomain, keys: ["onboarded"])])
            #expect(actual.summary(of: .userDefaults) == "1 key")
            #expect(actual.lines(of: .userDefaults) == [PlanLine(text: "onboarded", detail: nil)])
        }

        @Test("Keychain lists each item by service and account, or by label, with its class")
        func keychain() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let expected = [
                PlanLine(text: "api.example.com · alice", detail: "Password"),
                PlanLine(text: "refresh · alice", detail: "Password"),
                PlanLine(text: "Signing key", detail: "Key")
            ]

            let actual = await seeded.appState.plan(includingDebugDrawer: false)

            #expect(actual.lines(of: .keychain) == expected)
            #expect(actual.summary(of: .keychain) == "3 items")
            #expect(actual.problem(of: .keychain) == nil)
        }

        @Test("A keychain that can't be read is unavailable, with Security's message and code, and lists nothing")
        func keychainUnavailable() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            seeded.keychain.readError = KeychainError(status: errSecMissingEntitlement)

            let actual = await seeded.appState.plan(includingDebugDrawer: false)

            #expect(actual.keychain == .unavailable(KeychainError(status: errSecMissingEntitlement)))
            #expect(actual.summary(of: .keychain) == "Unavailable")
            #expect(actual.lines(of: .keychain).isEmpty)
            #expect(actual.problem(of: .keychain)?.hasSuffix("(-34018)") == true)
        }

        @Test("Files lists each area's entries, descending only where something is kept, never DebugDrawer's, the group's preferences or caches")
        func files() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let expected = [
                "Documents/Drafts", "Documents/notes.txt",
                "Application Support/com.example.app/store.sqlite", "Application Support/link-out",
                "tmp/scratch.tmp",
                "group.com.example/Library/Other", "group.com.example/Shared"
            ]

            let actual = await seeded.appState.plan(includingDebugDrawer: false)

            #expect(actual.files.map(\.displayPath) == expected)
        }

        @Test("Including DebugDrawer lists its export at the area's top and the app folder that held its crash reports, whole")
        func filesIncludingDebugDrawer() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let expected = [
                "Documents/DebugDrawer Export.txt", "Documents/Drafts", "Documents/notes.txt",
                "Application Support/com.example.app", "Application Support/link-out",
                "tmp/scratch.tmp",
                "group.com.example/Library/Other", "group.com.example/Shared"
            ]

            let actual = await seeded.appState.plan(includingDebugDrawer: true)

            #expect(actual.files.map(\.displayPath) == expected)
        }

        @Test("Sizes count the files under a folder; a link counts as nothing and what it points to isn't listed")
        func fileSizes() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }

            let actual = await seeded.appState.plan(includingDebugDrawer: false)
            let sizes = Dictionary(uniqueKeysWithValues: actual.files.map { ($0.displayPath, $0.byteCount) })

            #expect(sizes["Documents/Drafts"] == 3)
            #expect(sizes["Documents/notes.txt"] == 5)
            #expect(sizes["Application Support/link-out"] == 0)
            #expect(!actual.files.contains { $0.displayPath.contains("secret") })
            #expect(actual.summary(of: .files) == "7 items · \(ResetPlan.bytes(5 + 3 + 10 + 7 + 1 + 1))")
        }

        @Test("Caches lists the app's and the group's caches, keeping Caches/DebugDrawer unless included")
        func caches() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }

            let kept = await seeded.appState.plan(includingDebugDrawer: false)
            let included = await seeded.appState.plan(includingDebugDrawer: true)

            #expect(kept.caches.map(\.displayPath) == ["Caches/thumbs", "group.com.example/Library/Caches/g.cache"])
            #expect(included.caches.map(\.displayPath) == ["Caches/DebugDrawer", "Caches/thumbs", "group.com.example/Library/Caches/g.cache"])
        }

        @Test("Outside the sandbox, Caches lists Caches/<bundle identifier>/DebugDrawer with its recordings only when DebugDrawer is included")
        func unsandboxedCaches() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "AppStateReset-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let ownCaches = root.appending(path: "Caches/com.example.app")
            for (path, contents) in ["DebugDrawer/Recordings/a.mov": "movie", "thumbs/1.png": "png"] {
                let url = ownCaches.appending(path: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: url)
            }
            try Data("other".utf8).write(to: root.appending(path: "Caches/other.cache"))
            // As AppContainer.current lays out a Mac app outside the sandbox.
            let sut = AppContainer(
                files: [],
                caches: [FileArea(name: "Caches/com.example.app", directory: ownCaches)],
                kept: [],
                appFolderName: "com.example.app"
            )
            let expectedKept = ["Caches/com.example.app/thumbs"]
            let expectedIncluded = ["Caches/com.example.app/DebugDrawer", "Caches/com.example.app/thumbs"]
            let expectedRecordingsBytes: Int64 = 5

            let kept = await sut.entries(in: sut.caches, includingDebugDrawer: false)
            let included = await sut.entries(in: sut.caches, includingDebugDrawer: true)

            #expect(kept.map(\.displayPath) == expectedKept)
            #expect(included.map(\.displayPath) == expectedIncluded)
            #expect(included.first?.byteCount == expectedRecordingsBytes)
        }

        @Test("An area that is missing, or is itself a link, lists nothing; an empty one reads Empty")
        func missingAndLinkedAreas() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "AppStateReset-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root.appending(path: "Elsewhere"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: root.appending(path: "Elsewhere/file"))
            try FileManager.default.createSymbolicLink(at: root.appending(path: "Linked"), withDestinationURL: root.appending(path: "Elsewhere"))
            try FileManager.default.createDirectory(at: root.appending(path: "Empty"), withIntermediateDirectories: true)
            let sut = AppContainer(
                files: [
                    FileArea(name: "Missing", directory: root.appending(path: "Missing")),
                    FileArea(name: "Linked", directory: root.appending(path: "Linked")),
                    FileArea(name: "Empty", directory: root.appending(path: "Empty"))
                ],
                caches: [], kept: [], appFolderName: "com.example.app"
            )

            let actual = await sut.entries(in: sut.files, includingDebugDrawer: false)

            #expect(actual.isEmpty)
            #expect(ResetPlan(
                defaults: [], keychain: .items([]), files: actual, caches: [], cookies: [], urlCache: URLCacheUsage(disk: 0, memory: 0)
            ).summary(of: .files) == "Empty")
        }

        @Test("Cookies list each domain with its count, from both stores")
        func cookies() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let expected = [PlanLine(text: "example.com", detail: "2 cookies"), PlanLine(text: "other.org", detail: "1 cookie")]

            let actual = await seeded.appState.plan(includingDebugDrawer: false)

            #expect(actual.lines(of: .cookies) == expected)
            #expect(actual.summary(of: .cookies) == "3 cookies")
        }

        @Test("The URL cache shows its disk and memory usage, and the app's cleanup its title")
        func urlCacheAndCleanup() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let expected = [
                PlanLine(text: "On disk", detail: ResetPlan.bytes(2_000_000)),
                PlanLine(text: "In memory", detail: ResetPlan.bytes(500_000))
            ]

            let actual = await seeded.appState.plan(includingDebugDrawer: false)

            #expect(actual.urlCache == URLCacheUsage(disk: 2_000_000, memory: 500_000))
            #expect(actual.lines(of: .urlCache) == expected)
            #expect(actual.summary(of: .urlCache) == "\(ResetPlan.bytes(2_000_000)) on disk")
            #expect(actual.lines(of: .appCleanup) == [PlanLine(text: "Close the orders database", detail: nil)])
            #expect(actual.categories == AppStateReset.Category.allCases)
        }

        @Test("Without a cleanup from the app, there is no App Cleanup category")
        func noCleanup() {
            let sut = ResetPlan(defaults: [], keychain: .items([]), files: [], caches: [], cookies: [], urlCache: URLCacheUsage(disk: 0, memory: 0))
            let expected: [AppStateReset.Category] = [.userDefaults, .keychain, .files, .caches, .cookies, .urlCache]

            #expect(sut.categories == expected)
            #expect(sut.lines(of: .appCleanup).isEmpty)
        }

        @Test("An empty file's size is written as a number, not spelled out")
        func zeroBytes() {
            let expected = Int64(0).formatted(.byteCount(style: .file, spellsOutZero: false))

            let actual = ResetPlan.bytes(0)

            #expect(actual == expected)
            #expect(actual.first == "0")
        }
    }
#endif
