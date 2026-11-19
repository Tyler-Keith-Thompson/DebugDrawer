import Darwin
import DebugDrawerReceiver
import Foundation
import os

// One connected stream socket, carrying framed messages. POSIX sockets with dispatch sources over
// Network.framework: an AF_UNIX socket and the calls on it behave the same on every Apple
// platform, watchOS included, and NWListener documents no Unix-domain listening. Nothing here
// knows the address family. `DebugDrawerRemote`'s network transport doesn't use it: it needs
// Network.framework for Bonjour, so it frames the same messages over an `NWConnection` instead.
//
// Reads run on one queue and writes on another, so a write that waits for a slow reader never
// stops this side reading, and two sides writing large snapshots at each other can't deadlock.
// The descriptor is closed on the write queue once the read source is cancelled, after every
// write queued before it, and `State.isClosed` (set first, under the lock) stops any write queued
// after it: a closed descriptor's number can be reused by the next `open`, and a late write
// must never land in someone else's file.

#if DEBUG
    /// One end of a connected stream socket: the messages read from it, and a way to send.
    final class SocketConnection: Sendable {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "SocketConnection")

        private struct State {
            var decoder = TransportFrameDecoder()
            var isClosed = false
        }

        private let descriptor: Int32
        private let writeQueue = DispatchQueue(label: "DebugDrawer.SocketConnection.write")
        private let source: any DispatchSourceRead
        private let state = OSAllocatedUnfairLock(initialState: State())
        /// The messages read, in order; it finishes when the peer closes, the stream can't be
        /// read on, or ``close()`` is called.
        let messages: AsyncStream<TransportMessage>

        /// Takes over `descriptor`, a connected stream socket, and starts reading it.
        init(descriptor: Int32) {
            self.descriptor = descriptor
            var noSignal: Int32 = 1
            // A write to a peer that has gone raises SIGPIPE, which would end the app; with this
            // the write fails with EPIPE instead.
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            let (messages, received) = AsyncStream<TransportMessage>.makeStream()
            self.messages = messages
            source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "DebugDrawer.SocketConnection.read"))
            source.setEventHandler { [self] in
                readAvailable(into: received)
            }
            source.setCancelHandler { [self] in
                markClosed()
                received.finish()
                writeQueue.async { [descriptor] in
                    Darwin.close(descriptor)
                }
            }
            source.resume()
        }

        /// Sends `message` as one frame, after every message sent before it. Does nothing once the
        /// connection is closed.
        func send(_ message: TransportMessage) {
            guard let frame = try? TransportFraming.frame(message) else {
                Self.logger.error("Couldn't encode a message for \(message.pluginID, privacy: .public)")
                return
            }
            writeQueue.async { [self] in
                guard !state.withLock(\.isClosed) else { return }
                if !write(frame) {
                    close()
                }
            }
        }

        /// Closes the connection once every message sent before this call is written, so the
        /// peer reads them before the end of the stream.
        func closeAfterSending() {
            writeQueue.async { [self] in
                close()
            }
        }

        /// Closes the connection: ``messages`` finishes, and nothing more is sent.
        func close() {
            markClosed()
            source.cancel()
        }

        /// Reads what the socket holds and yields the messages it completes; cancels the source at
        /// the end of the stream, or when it isn't this format.
        private func readAvailable(into received: AsyncStream<TransportMessage>.Continuation) {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR || errno == EAGAIN { return }
            guard count > 0 else {
                source.cancel()
                return
            }
            let bytes = Data(buffer[0 ..< count])
            // The decoder's error comes back as a Result rather than thrown out of `withLock` and
            // caught here: built -O, that do/catch crashed swift-frontend's CopyPropagation pass
            // ("Found a leaked owned value": the error's `any Error` box) in Swift 6.4.0 and
            // 6.4.2 (Xcode 27.1 beta, 27.2), which stopped every `just bench*` recipe (DD-249).
            let decoded = state.withLock { state in
                Result { () throws(TransportFrameDecoder.FrameTooLong) in try state.decoder.append(bytes) }
            }
            guard case let .success(bodies) = decoded else {
                Self.logger.error("Closed a socket that sent a frame longer than the format allows")
                source.cancel()
                return
            }
            for message in bodies.compactMap(TransportMessage.decoded(from:)) {
                received.yield(message)
            }
        }

        /// Writes all of `frame`, waiting while the socket's buffer is full; `false` when the peer
        /// has gone or the socket was shut down.
        private func write(_ frame: Data) -> Bool {
            frame.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return true }
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(descriptor, base + offset, raw.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        return false
                    }
                    offset += written
                }
                return true
            }
        }

        /// Marks the connection closed and shuts the socket down, once: a write blocked on a full
        /// buffer returns, and the peer reads the end of the stream.
        private func markClosed() {
            state.withLock { state in
                guard !state.isClosed else { return }
                state.isClosed = true
                shutdown(descriptor, SHUT_RDWR)
            }
        }
    }
#endif
