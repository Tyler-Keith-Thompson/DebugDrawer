@testable import DebugDrawerLocationPlugin
import Foundation

/// GPX files the test lays out by URL, each a track or the error reading it gives; any other URL
/// is unreadable. Nothing touches the disk.
@MainActor
final class FakeGPXFileReading: GPXFileReading {
    private let files: [URL: Result<GPXTrack, GPXError>]
    /// The URLs read, in order.
    private(set) var reads: [URL] = []

    init(files: [URL: Result<GPXTrack, GPXError>] = [:]) {
        self.files = files
    }

    func track(at url: URL) throws(GPXError) -> GPXTrack {
        reads.append(url)
        return try (files[url] ?? .failure(.unreadable)).get()
    }
}
