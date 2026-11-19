import Darwin
import Foundation

// Change notification for the app-group store: a dispatch source on the directory's vnode, which
// the kernel fires when an entry is added, removed or renamed in it, by this process or any other.
// Rejected: NSFilePresenter (across processes it goes through file coordination, which both apps
// would have to use for every write, and it delivers on an operation queue), a Darwin notification
// (a name both sides must agree on, and a second step to read what changed; the directory's own
// event is both), and polling.

/// Says when a directory's entries change.
package final class DirectoryWatcher: Sendable {
    private let source: any DispatchSourceFileSystemObject
    /// One element after each change; changes that land before the reader takes one are
    /// folded into it. Finishes on ``cancel()``.
    package let changes: AsyncStream<Void>

    /// Watches `directory`, or returns `nil` when it can't be opened.
    package init?(directory: URL) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let (changes, changed) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.changes = changes
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue(label: "DebugDrawer.DirectoryWatcher")
        )
        source.setEventHandler {
            changed.yield()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
            changed.finish()
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    /// Stops watching.
    package func cancel() {
        source.cancel()
    }
}
