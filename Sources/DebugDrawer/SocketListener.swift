import Darwin
import Foundation
import os

// A listening Unix domain socket, apart from the server so it can stop listening when dropped:
// a main-actor server can't touch its state from a nonisolated deinit, and this holds only
// what's safe from any thread. The path is unlinked in `cancel()`, synchronously and once, so a
// server stopped and started again on the same path never has its new socket removed by the old
// one's late cleanup.

#if DEBUG
    /// A Unix domain socket listening at a path, handing out each connection made to it.
    final class SocketListener: Sendable {
        private let path: String
        private let source: any DispatchSourceRead
        private let isCancelled = OSAllocatedUnfairLock(initialState: false)
        /// Each connected socket's descriptor, blocking, for the receiver to take over; finishes
        /// when the listener is cancelled.
        let accepted: AsyncStream<Int32>

        /// Makes a socket at `path` and listens on it.
        ///
        /// - Throws: ``DebugDrawerTransportError/socketPathTooLong`` or
        ///   ``DebugDrawerTransportError/cannotServe``.
        init(path: String) throws(DebugDrawerTransportError) {
            guard let address = UnixSocketAddress.make(path) else { throw .socketPathTooLong }
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw .cannotServe }
            guard UnixSocketAddress.withSocketAddress(address, { bind(descriptor, $0, $1) }) == 0,
                  listen(descriptor, SOMAXCONN) == 0 else {
                Darwin.close(descriptor)
                throw .cannotServe
            }
            // Non-blocking, so the accept loop ends when no connection waits, and one that leaves
            // before it is accepted can't stall it.
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            self.path = path
            let (accepted, acceptedContinuation) = AsyncStream<Int32>.makeStream()
            self.accepted = accepted
            source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "DebugDrawer.SocketListener"))
            source.setEventHandler {
                while true {
                    let client = accept(descriptor, nil, nil)
                    guard client >= 0 else { return }
                    _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
                    acceptedContinuation.yield(client)
                }
            }
            source.setCancelHandler {
                Darwin.close(descriptor)
                acceptedContinuation.finish()
            }
            source.resume()
        }

        deinit {
            cancel()
        }

        /// Stops listening and removes the socket's file. Connections already made stay.
        func cancel() {
            let wasCancelled = isCancelled.withLock { isCancelled in
                defer { isCancelled = true }
                return isCancelled
            }
            guard !wasCancelled else { return }
            unlink(path)
            source.cancel()
        }
    }
#endif
