import DebugDrawer
import Foundation
import Testing

/// An interception plugin that keeps what it intercepts (requests, file calls, render counts, the
/// app's location managers), with what the contract's capture checks need: a call to make, tagged
/// with a marker, and the markers of what the plugin keeps.
@MainActor
public protocol CaptureContract: InterceptionContract {
    /// Sets how many calls the plugin keeps.
    func limitCapture(to count: Int) throws

    /// Makes one call the plugin keeps, as the app would, tagged `marker`, and returns once the
    /// app has its result.
    func makeCapturedCall(_ marker: String) async throws

    /// Waits until the plugin holds the call tagged `marker`, then returns the markers of every
    /// call it holds that this conformance made; untagged ones are left out.
    func capturedMarkers(through marker: String) async throws -> [String]

    /// How many calls the plugin holds, tagged or not.
    func capturedCount() -> Int
}

public extension CaptureContract {
    /// Checks that a plugin installed twice, and in a second drawer, keeps one call once.
    func checkCapturesOnceInstalledTwice(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withTwoDrawers { first, second in
            let marker = Self.marker("once")
            install(in: first)
            install(in: first)
            install(in: second)

            try await makeCapturedCall(marker)
            let actual = try await capturedMarkers(through: marker).filter { $0 == marker }.count

            #expect(actual == 1, "One call was kept \(actual) times", sourceLocation: sourceLocation)
        }
    }

    /// Checks that capture is bounded: past `limit` calls the plugin holds at most `limit`, the
    /// newest, and still the latest.
    ///
    /// - Parameter limit: The bound to set; the check makes twice as many calls and one more.
    func checkBoundedCapture(limit: Int = 3, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withTwoDrawers { drawer, _ in
            let markers = (0 ... limit * 2).map { Self.marker("bounded\($0)") }
            install(in: drawer)
            try limitCapture(to: limit)

            for marker in markers {
                try await makeCapturedCall(marker)
            }
            let latest = try #require(markers.last)
            let actual = try await capturedMarkers(through: latest)
            let held = capturedCount()

            #expect(held <= limit, "The plugin held \(held) calls past a limit of \(limit)", sourceLocation: sourceLocation)
            #expect(
                Set(actual).isSubset(of: markers.suffix(limit)),
                "The plugin kept older calls than the newest \(limit): \(actual)",
                sourceLocation: sourceLocation
            )
            #expect(actual.contains(latest), sourceLocation: sourceLocation)
        }
    }

    /// Checks that a plugin installed and removed again keeps nothing: what it held is forgotten,
    /// a call made while it is removed isn't kept, and once installed again it keeps calls again.
    func checkCapturesNothingUninstalled(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withTwoDrawers { drawer, _ in
            let installed = Self.marker("installed")
            let uninstalled = Self.marker("uninstalled")
            let reinstalled = Self.marker("reinstalled")
            install(in: drawer)
            try await makeCapturedCall(installed)
            _ = try await capturedMarkers(through: installed)

            uninstall(from: drawer)
            try await makeCapturedCall(uninstalled)
            install(in: drawer)
            try await makeCapturedCall(reinstalled)
            let actual = try await capturedMarkers(through: reinstalled)

            #expect(actual == [reinstalled], "A plugin removed and installed again held \(actual)", sourceLocation: sourceLocation)
        }
    }

    /// A marker no other call shares: `name` and a UUID.
    static func marker(_ name: String) -> String {
        "\(name)-\(UUID().uuidString)"
    }
}
