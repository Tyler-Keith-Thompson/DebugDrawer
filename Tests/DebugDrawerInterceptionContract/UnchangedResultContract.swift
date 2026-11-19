import DebugDrawer
import Testing

/// An interception plugin whose effect on the app's results the contract checks: a call the plugin
/// intercepts, made as the app makes it, returns the same with the plugin installed as without,
/// beyond what the plugin is for (a mock rule, a spoofed location), which the call leaves off.
@MainActor
public protocol UnchangedResultContract: InterceptionContract {
    /// What the app sees from the call: its result, its error, what it wrote.
    associatedtype AppResult: Equatable

    /// Makes one call the plugin intercepts, as the app would, and returns what the app saw.
    func makeAppCall() async throws -> AppResult
}

public extension UnchangedResultContract {
    /// Checks that the app sees the same from ``makeAppCall()`` before the plugin is installed,
    /// while it is, and after it is removed.
    func checkUnchangedResult(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withTwoDrawers { drawer, _ in
            let expected = try await makeAppCall()

            install(in: drawer)
            let actual = try await makeAppCall()
            uninstall(from: drawer)
            let afterUninstall = try await makeAppCall()

            #expect(actual == expected, "The app saw a different result with the plugin installed", sourceLocation: sourceLocation)
            #expect(afterUninstall == expected, "The app saw a different result after the plugin was removed", sourceLocation: sourceLocation)
        }
    }
}
