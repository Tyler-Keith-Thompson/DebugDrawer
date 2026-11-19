import DebugDrawer
import Testing

/// A capturing plugin whose filter on the drawer's own activity the contract checks: work the
/// drawer does itself (its file work under `DebugDrawerActivity.isDrawerWork`, the requests the
/// Network plugin forwards, the drawer's own views) is never kept beside the app's.
@MainActor
public protocol DrawerActivityContract: CaptureContract {
    /// Does what the drawer itself does that the plugin would otherwise intercept, tagged `marker`
    /// where it can be, and returns once that work is done.
    func makeDrawerCall(_ marker: String) async throws
}

public extension DrawerActivityContract {
    /// Checks that the drawer's own work adds nothing to what the plugin holds, while the app's
    /// calls on either side of it are kept.
    func checkLeavesOutDrawerActivity(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withTwoDrawers { drawer, _ in
            let before = Self.marker("before")
            let drawerWork = Self.marker("drawer")
            let after = Self.marker("after")
            install(in: drawer)
            try await makeCapturedCall(before)
            let expected = try await Set(capturedMarkers(through: before)).union([after])

            try await makeDrawerCall(drawerWork)
            try await makeCapturedCall(after)
            let actual = try await Set(capturedMarkers(through: after))

            #expect(actual == expected, "The drawer's own work was kept: \(actual.subtracting(expected).sorted())", sourceLocation: sourceLocation)
        }
    }
}
