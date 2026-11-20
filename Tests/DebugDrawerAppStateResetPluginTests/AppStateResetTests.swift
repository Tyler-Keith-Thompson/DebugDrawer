#if DEBUG
    import Foundation
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import Security
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStateResetTests {
        @Test("Resetting one category deletes what it listed and leaves every other category as it was", arguments: AppStateReset.Category.allCases)
        func oneCategory(category: AppStateReset.Category) async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: false)
            let before = seeded.paths()
            let listed = category == .files ? plan.files : category == .caches ? plan.caches : []
            let expectedPaths = before.filter { path in
                listed.contains { path == seeded.relativePath(of: $0) || path.hasPrefix(seeded.relativePath(of: $0) + "/") }
            }

            let actual = await seeded.appState.reset([category], of: plan)
            let removedPaths = before.subtracting(seeded.paths())

            #expect(actual.categories == [category])
            #expect(removedPaths == expectedPaths)
            #expect(Set(seeded.preferences.removed.values.joined()) == (category == .userDefaults ? ["counter", "onboarded", "shared"] : []))
            #expect(seeded.keychain.deleted.count == (category == .keychain ? 3 : 0))
            #expect(seeded.cookies.deleted.count == (category == .cookies ? 3 : 0))
            #expect(seeded.responseCache.removals == (category == .urlCache ? 1 : 0))
            #expect(seeded.cleanupCounter.runs == (category == .appCleanup ? 1 : 0))
        }

        @Test("Each category reports how many things it cleared")
        func outcomes() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: false)
            let expected: [AppStateReset.Category: ResetOutcome] = [
                .userDefaults: .cleared(3), .keychain: .cleared(3), .files: .cleared(7), .caches: .cleared(2),
                .cookies: .cleared(3), .urlCache: .cleared(1), .appCleanup: .cleared(1)
            ]

            let actual = await seeded.appState.reset(Set(AppStateReset.Category.allCases), of: plan)

            #expect(actual.outcomes == expected)
            #expect(!actual.hasFailures)
        }

        @Test("A reset keeps DebugDrawer's keys and files, the app group's preferences and the link's target")
        func keepsDebugDrawer() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: false)
            let expected: Set = [
                "Documents", "Documents/DebugDrawer Export.txt",
                "Application Support", "Application Support/com.example.app",
                "Application Support/com.example.app/DebugDrawer Crash Reports",
                "Application Support/com.example.app/DebugDrawer Crash Reports/r1.json",
                "tmp", "Caches", "Caches/DebugDrawer", "Caches/DebugDrawer/Recordings", "Caches/DebugDrawer/Recordings/a.mov",
                "group", "group/Library", "group/Library/Preferences", "group/Library/Preferences/group.plist", "group/Library/Caches",
                "Outside", "Outside/secret.txt"
            ]

            _ = await seeded.appState.reset(Set(AppStateReset.Category.allCases), of: plan)
            let actual = seeded.paths()

            #expect(actual == expected)
            #expect(seeded.preferences.domains[SeededAppState.appDomain] == ["com.debugdrawer.layout"])
        }

        @Test("A link out of the container is listed and deleted as a link; what it points to survives")
        func linkNotFollowed() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let link = seeded.root.appending(path: "Application Support/link-out")
            let target = seeded.root.appending(path: "Outside/secret.txt")
            let plan = await seeded.appState.plan(includingDebugDrawer: true)
            let listed = try #require(plan.files.first { $0.displayPath == "Application Support/link-out" })

            _ = await seeded.appState.reset([.files, .caches], of: plan)
            let linkRemains = (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))) != nil
            let actual = try String(contentsOf: target, encoding: .utf8)

            #expect(listed.byteCount == 0)
            #expect(!linkRemains)
            #expect(actual == "secret")
            #expect(!plan.files.contains { $0.displayPath.hasPrefix("Application Support/link-out/") })
        }

        @Test("Including DebugDrawer deletes its keys and files too, but never an area itself")
        func includesDebugDrawer() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: true)
            let expected: Set = [
                "Documents", "Application Support", "tmp", "Caches",
                "group", "group/Library", "group/Library/Preferences", "group/Library/Preferences/group.plist", "group/Library/Caches",
                "Outside", "Outside/secret.txt"
            ]

            _ = await seeded.appState.reset(Set(AppStateReset.Category.allCases), of: plan)
            let actual = seeded.paths()

            #expect(actual == expected)
            #expect(seeded.preferences.domains[SeededAppState.appDomain] == [])
        }

        // Every input there is (2^7 selections, twice), rather than a random sample of them. Each is a
        // test case of its own, so the suite's time limit applies to each one rather than to all
        // 256 together, which a loaded simulator took past a minute.
        @Test(
            "Whatever is selected, the reset deletes exactly what the plan lists: every subset of categories, with and without DebugDrawer's own",
            arguments: [false, true], 0 ..< (1 << AppStateReset.Category.allCases.count)
        )
        func deletesExactlyThePlan(includesDebugDrawer: Bool, mask: Int) async throws {
            let categories = AppStateReset.Category.allCases
            let selection = Set(categories.indices.filter { mask & (1 << $0) != 0 }.map { categories[$0] })
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: includesDebugDrawer)
            let before = seeded.paths()
            let listedEntries = (selection.contains(.files) ? plan.files : []) + (selection.contains(.caches) ? plan.caches : [])
            let listedEntryPaths = listedEntries.map(seeded.relativePath(of:))
            let listedPaths = before.filter { path in
                listedEntryPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
            }
            let listedKeys = selection.contains(.userDefaults)
                ? Set(plan.defaults.flatMap { domain in domain.keys.map { "\(domain.name)/\($0)" } })
                : []
            let listedItems = selection.contains(.keychain) ? plan.keychain : .items([])
            let listedCookies = selection.contains(.cookies) ? Set(plan.cookies) : []

            _ = await seeded.appState.reset(selection, of: plan)
            let deletedPaths = before.subtracting(seeded.paths())
            let deletedKeys = Set(seeded.preferences.removed.flatMap { domain, keys in keys.map { "\(domain)/\($0)" } })

            #expect(deletedPaths == listedPaths, "\(selection), DebugDrawer \(includesDebugDrawer)")
            #expect(deletedKeys == listedKeys, "\(selection)")
            #expect(KeychainInventory.items(seeded.keychain.deleted) == listedItems, "\(selection)")
            #expect(Set(seeded.cookies.deleted) == listedCookies, "\(selection)")
            #expect(seeded.responseCache.removals == (selection.contains(.urlCache) ? 1 : 0), "\(selection)")
            #expect(seeded.cleanupCounter.runs == (selection.contains(.appCleanup) ? 1 : 0), "\(selection)")
        }

        @Test("A keychain that can't be read fails the category with its status and deletes nothing")
        func keychainUnavailable() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            seeded.keychain.readError = KeychainError(status: errSecMissingEntitlement)
            let plan = await seeded.appState.plan(includingDebugDrawer: false)
            let expected = ResetOutcome.failed(cleared: 0, failures: [.keychainUnavailable(KeychainError(status: errSecMissingEntitlement))])

            let actual = await seeded.appState.reset([.keychain], of: plan)

            #expect(actual.outcomes[.keychain] == expected)
            #expect(actual.hasFailures)
            #expect(seeded.keychain.deleted.isEmpty)
        }

        @Test("An item the keychain won't delete is named with its status; the others are deleted")
        func keychainItemRefused() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let refused = FakeKeychain.password(service: "refresh", account: "alice")
            seeded.keychain.refusals[refused.persistentReference] = errSecInteractionNotAllowed
            let plan = await seeded.appState.plan(includingDebugDrawer: false)
            let expected = ResetOutcome.failed(
                cleared: 2, failures: [.keychainItem("refresh · alice", KeychainError(status: errSecInteractionNotAllowed))]
            )

            let actual = await seeded.appState.reset([.keychain], of: plan)

            #expect(actual.outcomes[.keychain] == expected)
            #expect(seeded.keychain.stored == [refused])
        }

        @Test("A file that can't be deleted is named with why; the rest of the area is deleted")
        func fileRefused() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let locked = seeded.root.appending(path: "Documents/Drafts")
            // A folder that can't be written keeps what is in it.
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path(percentEncoded: false))
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false)) }
            let plan = await seeded.appState.plan(includingDebugDrawer: false)

            let actual = await seeded.appState.reset([.files], of: plan)

            guard case let .failed(cleared, failures)? = actual.outcomes[.files], case let .file(path, reason)? = failures.first else {
                Issue.record("Expected a file failure, got \(String(describing: actual.outcomes[.files]))")
                return
            }
            #expect(cleared == 6)
            #expect(failures.count == 1)
            #expect(path == "Documents/Drafts")
            #expect(!reason.isEmpty)
            #expect(FileManager.default.fileExists(atPath: locked.appending(path: "a.txt").path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: seeded.root.appending(path: "Documents/notes.txt").path(percentEncoded: false)))
        }

        @Test("A file deleted since the plan was read is no failure")
        func fileAlreadyGone() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: false)
            try FileManager.default.removeItem(at: seeded.root.appending(path: "tmp/scratch.tmp"))

            let actual = await seeded.appState.reset([.files], of: plan)

            #expect(actual.outcomes[.files] == .cleared(7))
        }

        @Test("A cleanup that throws fails its category with the error's description, and the reset goes on")
        func cleanupFails() async throws {
            let seeded = try SeededAppState(cleanupError: CocoaError(.fileLocking))
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: false)

            let actual = await seeded.appState.reset([.appCleanup, .cookies], of: plan)

            guard case let .failed(cleared, failures)? = actual.outcomes[.appCleanup], case let .cleanup(reason)? = failures.first else {
                Issue.record("Expected a cleanup failure, got \(String(describing: actual.outcomes[.appCleanup]))")
                return
            }
            #expect(cleared == 0)
            #expect(reason == CocoaError(.fileLocking).localizedDescription)
            #expect(actual.outcomes[.cookies] == .cleared(3))
        }

        @Test("The app's cleanup runs before any file is deleted")
        func cleanupRunsFirst() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let plan = await seeded.appState.plan(includingDebugDrawer: false)
            let expected: [AppStateReset.Category] = [.appCleanup, .keychain, .userDefaults, .cookies, .urlCache, .caches, .files]

            #expect(AppStateReset.Category.resetOrder == expected)
            #expect(Set(AppStateReset.Category.resetOrder) == Set(AppStateReset.Category.allCases))
            _ = await seeded.appState.reset(Set(AppStateReset.Category.allCases), of: plan)
            #expect(seeded.cleanupCounter.runs == 1)
        }

        @Test("Failure messages name what failed and why")
        func failureMessages() {
            let error = KeychainError(status: errSecItemNotFound)

            #expect(ResetFailure.file("Documents/a", reason: "No permission").message == "Documents/a: No permission")
            #expect(ResetFailure.cleanup("Locked").message == "The app's cleanup failed: Locked")
            #expect(ResetFailure.keychainItem("svc · acct", error).message == "svc · acct: \(error.message)")
            #expect(ResetFailure.keychainUnavailable(error).message == "The keychain couldn't be read: \(error.message)")
            #expect(error.message.hasSuffix("(-25300)"))
        }
    }
#endif
