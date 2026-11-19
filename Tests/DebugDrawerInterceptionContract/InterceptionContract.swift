import DebugDrawer
import Foundation
import Testing

/// A plugin that changes how the app's own calls run (swizzling, a URL protocol, a hook), as the
/// interception contract in the plugin-authoring guide describes it, with the specifics the
/// contract's checks need from it.
///
/// The checks are methods on the conformance; a test target runs each in a child process of its
/// own, as installing changes the whole process:
///
/// ```swift
/// @Test("Installing twice changes the process as installing once does")
/// func idempotentInstall() async {
///     await #expect(processExitsWith: .success) {
///         try await NetworkContract().checkIdempotentInstall()
///     }
/// }
/// ```
///
/// The checks record their failures with `#expect`, and leave the plugin installed or not as their
/// last step left it: the child process ends with them.
@MainActor
public protocol InterceptionContract {
    /// What installing changes in the process, read at one moment: the implementations of the
    /// methods it replaces, the classes it registers, the switches it turns on.
    associatedtype ProcessState: Equatable

    /// Installs the plugin in `drawer` as an app does, through its `install*()` call.
    func install(in drawer: DebugDrawer)

    /// Removes the plugin from `drawer` as an app does, through `unregisterGlobal(id:)`.
    func uninstall(from drawer: DebugDrawer)

    /// What installing changes in the process, as it is now.
    func processState() throws -> ProcessState
}

public extension InterceptionContract {
    /// Checks that installing is idempotent: installing again in the same drawer, and in a second
    /// drawer, leaves the process as installing once did, and installing changes something.
    func checkIdempotentInstall(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withTwoDrawers { first, second in
            let before = try processState()

            install(in: first)
            let once = try processState()
            install(in: first)
            install(in: second)
            let actual = try processState()

            #expect(once != before, "Installing changed nothing the contract reads", sourceLocation: sourceLocation)
            #expect(actual == once, "Installing twice changed the process again", sourceLocation: sourceLocation)
        }
    }

    /// Checks that uninstalling is reversible: once the last drawer holding the plugin removes it,
    /// the process is as it was before the first install; a second removal changes nothing; and an
    /// install after that changes the process again, and its uninstall puts it back too.
    func checkReversibleUninstall(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withTwoDrawers { first, second in
            let expected = try processState()
            install(in: first)
            install(in: second)
            let installed = try processState()

            uninstall(from: first)
            let whileSecondHoldsIt = try processState()
            uninstall(from: second)
            let actual = try processState()
            uninstall(from: second)
            let afterSecondUninstall = try processState()
            install(in: first)
            let reinstalled = try processState()
            uninstall(from: first)
            let afterReinstall = try processState()

            #expect(whileSecondHoldsIt == installed, "Removing the plugin from one drawer undid it for another", sourceLocation: sourceLocation)
            #expect(actual == expected, "Uninstalling didn't put back what installing changed", sourceLocation: sourceLocation)
            #expect(afterSecondUninstall == expected, "A second uninstall changed the process", sourceLocation: sourceLocation)
            // Not `== installed`: a replacement made from a block is a new implementation each time.
            #expect(reinstalled != expected, "Installing after an uninstall changed nothing", sourceLocation: sourceLocation)
            #expect(afterReinstall == expected, "Uninstalling after a reinstall didn't put the process back", sourceLocation: sourceLocation)
        }
    }
}

extension InterceptionContract {
    /// Runs `body` with two drawers of their own, each keeping what it saves in a `UserDefaults`
    /// suite of its own, which is removed afterwards.
    func withTwoDrawers(_ body: (DebugDrawer, DebugDrawer) async throws -> Void) async throws {
        let suites = ["InterceptionContract.\(UUID().uuidString)", "InterceptionContract.\(UUID().uuidString)"]
        defer {
            for suite in suites {
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
        }
        let first = try #require(UserDefaults(suiteName: suites[0]))
        let second = try #require(UserDefaults(suiteName: suites[1]))
        try await body(DebugDrawer(defaults: first), DebugDrawer(defaults: second))
    }
}
