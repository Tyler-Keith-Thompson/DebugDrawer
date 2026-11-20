import Foundation

/// The URL cache the plugin clears, `URLCache.shared` in an app.
@MainActor
package protocol ResponseCache {
    /// The bytes its responses take on disk.
    var currentDiskUsage: Int { get }
    /// The bytes its responses take in memory.
    var currentMemoryUsage: Int { get }
    /// Deletes every cached response.
    func removeAllCachedResponses()
}

extension URLCache: ResponseCache {}

/// What the URL cache holds, as the list shows it.
package struct URLCacheUsage: Hashable, Sendable {
    /// Bytes on disk.
    package let disk: Int
    /// Bytes in memory.
    package let memory: Int
}
