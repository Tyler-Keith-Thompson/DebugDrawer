@testable import DebugDrawerFileBrowserPlugin
import Foundation

/// A file system that reads the real one and refuses every change, as a read-only volume does.
struct FailingFileSystem: FileSystem {
    let error = CocoaError(.fileWriteNoPermission)

    func item(at url: URL) async throws -> FileItem {
        try await LocalFileSystem().item(at: url)
    }

    func contents(of url: URL) async throws -> [FileItem] {
        try await LocalFileSystem().contents(of: url)
    }

    func totalSize(of url: URL) async throws(CancellationError) -> Int64 {
        try await LocalFileSystem().totalSize(of: url)
    }

    func read(_ url: URL, upTo limit: Int) async throws -> Data {
        try await LocalFileSystem().read(url, upTo: limit)
    }

    func remove(_ url: URL) async throws {
        throw error
    }

    func move(_ url: URL, to destination: URL) async throws {
        throw error
    }

    func copy(_ url: URL, to destination: URL) async throws {
        throw error
    }
}
