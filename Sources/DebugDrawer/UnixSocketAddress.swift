import Darwin
import Foundation
import os

// A Unix domain socket's address holds a path of at most 103 bytes (`sun_path` is 104, with its
// terminating zero) on every Apple platform, and an app group's container can be longer than that:
// in the iOS simulator it sits under the Mac user's CoreSimulator device folder, about 170 bytes
// before the socket's own name. A path that fits is used as it is. A longer one is reached by its
// file name, relative to its directory: the process's working directory is changed to that
// directory for the one `bind` or `connect`, then changed back, under a lock, so two of these calls
// never interleave. Only the file name then has to fit, so a socket can live anywhere the app can
// reach. `bind` resolves the relative name to the directory's vnode, so the socket made is the
// one at the long path, and `lstat`, `unlink` and the sidecar's directory watch use that path as
// it is.
//
// Rejected: `bindat`/`connectat` (in the kernel, but in no public header of any SDK, so private
// API), `pthread_fchdir_np` for a working directory per thread (private too), an address longer
// than `sockaddr_un` with `sun_len` past 106 (XNU accepts up to 253 bytes, but no document says
// so, and it is outside the `sun_path` limit), and a short symbolic link to the directory (no short
// directory both apps of a group can write to exists on iOS, where each app's `/tmp` is its own).
// The working directory is the process's, so another thread resolving a relative path during
// the call would resolve it there; apps use absolute paths (every Foundation directory API gives
// one), and the change lasts one system call.

#if DEBUG
    /// Where a Unix domain socket is, as the socket calls take it.
    enum UnixSocketAddress {
        /// The most bytes of path an address holds: 103, and a terminating zero.
        static let maximumPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

        /// Serializes changes of the working directory, which every thread of the process shares.
        private static let workingDirectory = OSAllocatedUnfairLock()

        /// Whether a socket at `path` can be bound or connected to: the path fits an address, or
        /// its file name does.
        static func isReachable(_ path: String) -> Bool {
            address(path) != nil || address(fileName(of: path)) != nil
        }

        /// Binds `descriptor`, a Unix domain socket, to `path`, making the socket's file there.
        ///
        /// - Returns: `false` when it can't: `errno` says why.
        static func bind(_ descriptor: Int32, to path: String) -> Bool {
            call(path) { Darwin.bind(descriptor, $0, $1) } == 0
        }

        /// A new stream socket connected to `path`, or `nil` when nothing listens there.
        static func connect(to path: String) -> Int32? {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            guard call(path, { Darwin.connect(descriptor, $0, $1) }) == 0 else {
                Darwin.close(descriptor)
                return nil
            }
            return descriptor
        }

        /// Calls `body`, a socket call, with the address of `path`: the path itself when it fits,
        /// or else its file name, with the working directory changed to the path's directory for
        /// the call.
        private static func call(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
            if let address = address(path) {
                return withSocketAddress(address, body)
            }
            guard let address = address(fileName(of: path)) else {
                errno = ENAMETOOLONG
                return -1
            }
            let directory = URL(filePath: path, directoryHint: .notDirectory).deletingLastPathComponent().path
            return workingDirectory.withLockUnchecked {
                // Search permission is all that changing back takes; reading "/" may be denied
                // in a sandbox, searching it never is.
                let previous = open(".", O_SEARCH | O_CLOEXEC)
                guard previous >= 0 else { return -1 }
                defer { Darwin.close(previous) }
                guard chdir(directory) == 0 else { return -1 }
                defer { _ = fchdir(previous) }
                return withSocketAddress(address, body)
            }
        }

        /// The last component of `path`.
        private static func fileName(of path: String) -> String {
            URL(filePath: path, directoryHint: .notDirectory).lastPathComponent
        }

        /// The address of `path`, or `nil` when the path is longer than an address holds.
        private static func address(_ path: String) -> sockaddr_un? {
            var address = sockaddr_un()
            let bytes = Array(path.utf8)
            guard !bytes.isEmpty, bytes.count <= maximumPathLength else { return nil }
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            return address
        }

        /// Calls `body` with `address` as the generic socket address the socket calls take.
        private static func withSocketAddress<Result>(
            _ address: sockaddr_un,
            _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result
        ) -> Result {
            withUnsafePointer(to: address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
        }
    }
#endif
