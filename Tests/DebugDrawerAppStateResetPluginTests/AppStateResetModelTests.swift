#if DEBUG
    import Foundation
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import Security
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStateResetModelTests {
        @Test("The model starts loading with every category selected, and reads the plan once when first shown")
        func load() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let sut = AppStateResetModel(appState: seeded.appState, process: FakeAppProcess())
            let initial = sut.state

            await sut.loadIfNeeded()
            let loaded = sut.state
            seeded.preferences.domains[SeededAppState.appDomain]?.insert("later")
            await sut.loadIfNeeded()

            #expect(initial == .loading)
            #expect(sut.selection == Set(AppStateReset.Category.allCases))
            #expect(loaded.plan?.summary(of: .userDefaults) == "3 keys")
            #expect(sut.state == loaded)
        }

        @Test("Without a cleanup from the app, App Cleanup isn't selected")
        func selectionWithoutCleanup() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let appState = AppState(
                domains: seeded.appState.domains, preferences: seeded.preferences, keychain: seeded.keychain,
                container: seeded.appState.container, cookies: seeded.cookies, responseCache: seeded.responseCache, cleanup: nil
            )

            let sut = AppStateResetModel(appState: appState, process: FakeAppProcess())

            #expect(!sut.selection.contains(.appCleanup))
            #expect(sut.selection.count == 6)
        }

        @Test("Refresh reads the plan again, and including DebugDrawer re-plans with its keys")
        func refresh() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let sut = AppStateResetModel(appState: seeded.appState, process: FakeAppProcess())
            await sut.loadIfNeeded()

            seeded.preferences.domains[SeededAppState.appDomain]?.insert("later")
            await sut.refresh()
            let refreshed = sut.state.plan?.summary(of: .userDefaults)
            await sut.setIncludesDebugDrawer(true)

            #expect(refreshed == "4 keys")
            #expect(sut.includesDebugDrawer)
            #expect(sut.state.plan?.summary(of: .userDefaults) == "5 keys")
        }

        @Test("Reset clears only the selected categories, then shows their outcomes over a fresh plan, and doesn't restart")
        func reset() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let process = FakeAppProcess()
            let sut = AppStateResetModel(appState: seeded.appState, process: process)
            await sut.loadIfNeeded()
            sut.selection = [.userDefaults, .files]

            await sut.reset(restarting: false)

            guard case let .finished(plan, result, restart) = sut.state else {
                Issue.record("Expected finished, got \(sut.state)")
                return
            }
            #expect(result.outcomes == [.userDefaults: .cleared(3), .files: .cleared(7)])
            #expect(restart == .none)
            #expect(plan.summary(of: .userDefaults) == "No keys")
            #expect(plan.summary(of: .files) == "Empty")
            #expect(plan.summary(of: .keychain) == "3 items")
            #expect(process.restarts == 0)
        }

        @Test("Reset and Restart restarts once everything is deleted and the defaults written")
        func resetAndRestart() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let process = FakeAppProcess(.relaunch)
            var removedAtRestart: [String: [String]] = [:]
            process.onRestart = { removedAtRestart = seeded.preferences.removed }
            let sut = AppStateResetModel(appState: seeded.appState, process: process)
            await sut.loadIfNeeded()

            await sut.reset(restarting: true)

            #expect(process.restarts == 1)
            #expect(removedAtRestart[SeededAppState.appDomain] == ["counter", "onboarded"])
            #expect(seeded.cookies.stored.isEmpty)
            #expect(sut.restartStyle == .relaunch)
        }

        @Test("When something isn't deleted, the app keeps running so the failure can be read")
        func restartHeldForFailures() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            seeded.keychain.readError = KeychainError(status: errSecMissingEntitlement)
            let process = FakeAppProcess()
            let sut = AppStateResetModel(appState: seeded.appState, process: process)
            await sut.loadIfNeeded()

            await sut.reset(restarting: true)

            guard case let .finished(_, result, restart) = sut.state else {
                Issue.record("Expected finished, got \(sut.state)")
                return
            }
            #expect(result.hasFailures)
            #expect(restart == .heldForFailures)
            #expect(process.restarts == 0)
        }

        @Test("A relaunch that can't start says why, and the app keeps running")
        func relaunchFails() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let process = FakeAppProcess(.relaunch)
            process.failure = RelaunchFailure(message: "The application can't be opened.")
            let sut = AppStateResetModel(appState: seeded.appState, process: process)
            await sut.loadIfNeeded()
            sut.selection = [.urlCache]

            await sut.reset(restarting: true)

            guard case let .finished(_, _, restart) = sut.state else {
                Issue.record("Expected finished, got \(sut.state)")
                return
            }
            #expect(restart == .failed(RelaunchFailure(message: "The application can't be opened.")))
        }

        @Test("Reset before the plan is read does nothing")
        func resetBeforeLoad() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let sut = AppStateResetModel(appState: seeded.appState, process: FakeAppProcess())

            await sut.reset(restarting: false)

            #expect(sut.state == .loading)
            #expect(seeded.preferences.removed.isEmpty)
        }
    }
#endif
