import Foundation

/// MetricKit's payloads in the debug drawer: the daily metrics and the diagnostics the system
/// delivers to the app, kept across launches.
///
/// ``install(directory:)`` subscribes to `MXMetricManager` where MetricKit exists (iOS, macOS,
/// visionOS; macOS reports a subset of the metrics), first keeping the payloads the system still
/// holds from before. MetricKit delivers to every subscriber, so an analytics SDK, Crash Reports
/// or Hangs subscribing as well still gets each payload.
///
/// The type exists in every build, so the calls compile unchanged in release, where they do
/// nothing.
public enum MetricKitPayloads {
    /// Where payloads are kept unless `install(directory:)` is given another: a folder in the
    /// app's Application Support directory, named after its bundle identifier, as on macOS that
    /// directory is shared by every app that isn't sandboxed.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
            .appending(path: "DebugDrawer MetricKit Payloads", directoryHint: .isDirectory)
    }

    /// Adds the MetricKit plugin and keeps every payload MetricKit delivers from now on: in debug
    /// builds only; in release it does nothing.
    ///
    /// Call it once at startup. It keeps the payloads the system still holds (MetricKit's past
    /// payloads) that aren't kept already, with the others (the newest fifty), raises the
    /// plugin's badge for every payload not yet opened, and posts a toast for each new one.
    /// Calling it again moves where payloads are kept and subscribes no second time.
    ///
    /// - Parameter directory: Where the payloads are kept.
    @MainActor
    public static func install(directory: URL = defaultDirectory) {
        #if DEBUG
            MetricKitPayloadsInstallation.install(directory: directory)
        #endif
    }

    /// Keeps a payload the app has from elsewhere, as if MetricKit had delivered it: one a device
    /// exported, one the app's own subscriber received, or a sample where MetricKit delivers
    /// nothing (the simulator). In debug builds after ``install(directory:)`` only; otherwise it
    /// does nothing.
    ///
    /// The period it covers is read from its `timeStampBegin` and `timeStampEnd`, else it is the
    /// moment it is added. A payload already kept, or JSON that isn't an object, adds nothing.
    ///
    /// - Parameters:
    ///   - json: The payload's `jsonRepresentation()`.
    ///   - kind: Whether it is a metric or a diagnostic payload.
    @MainActor
    public static func add(json: Data, kind: MetricKitPayloadKind) {
        #if DEBUG
            MetricKitPayloadsInstallation.add(json: json, kind: kind)
        #endif
    }
}
