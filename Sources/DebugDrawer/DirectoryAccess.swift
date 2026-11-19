import Darwin
import Foundation
import os

// How the socket and store servers and transports reach their directories in an app group's
// container, and how they fail when the system refuses: the sandbox without the group in the
// app's entitlements, macOS asking the person before one app reaches another's data and the
// person declining, or plain file permissions. Each of those comes back from the system call as
// EACCES or EPERM, which is told apart from every other failure and thrown as
// `DebugDrawerTransportError.accessDenied`, so a host can say what to fix. Nothing falls back to
// another directory: a transport that can't reach its own directory throws, and writes nowhere.
//
// The access check runs before the first write, so a directory that exists but can't be written
// or searched fails `start()` or `init` at once, rather than every later write failing into a log.
// It uses `faccessat` with `AT_EACCESS`, the effective IDs and the sandbox's own verdict, the same
// answer an `open` would get. Rejected: trying a write (it leaves a file behind on success and
// needs removing), and checking only the parent (a directory made earlier may have other modes).

#if DEBUG
    /// Makes and checks the directories the socket and store transports keep their files in.
    enum DirectoryAccess {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "DirectoryAccess")

        /// What a side needs of a directory, as `faccessat` takes it.
        enum Need {
            /// Reading its entries and searching it: a viewer watching a socket's directory.
            case read
            /// Reading, writing and searching it: a server's, or the store's, own directory.
            case readWrite

            fileprivate var mode: Int32 {
                switch self {
                case .read: R_OK | X_OK
                case .readWrite: R_OK | W_OK | X_OK
                }
            }
        }

        /// Makes `directory`, with any directories above it, if it doesn't exist, then checks this
        /// process may use it as `need` says.
        ///
        /// - Throws: ``DebugDrawerTransportError/accessDenied`` when the system refuses either
        ///   step, and `otherwise` when it fails for any other reason.
        static func prepare(_ directory: URL, need: Need, otherwise: DebugDrawerTransportError) throws(DebugDrawerTransportError) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                let code = posixCode(of: error)
                throw failure(code, at: directory.path, otherwise: otherwise)
            }
            guard faccessat(AT_FDCWD, directory.path, need.mode, AT_EACCESS) == 0 else {
                throw failure(errno, at: directory.path, otherwise: otherwise)
            }
        }

        /// The error a system call failing with `code` at `path` gives: ``DebugDrawerTransportError/accessDenied``
        /// for EACCES and EPERM, logged with the path, and `otherwise` for every other code.
        static func failure(_ code: Int32, at path: String, otherwise: DebugDrawerTransportError) -> DebugDrawerTransportError {
            guard isDenial(code) else { return otherwise }
            let reason = String(cString: strerror(code))
            let advice = DebugDrawerTransportError.accessDenied.localizedDescription
            logger.error("Access to \(path, privacy: .private) was refused (\(reason, privacy: .public)): \(advice, privacy: .public)")
            return .accessDenied
        }

        /// Whether `code` is the system refusing access, by permissions, the sandbox or the person.
        static func isDenial(_ code: Int32) -> Bool {
            code == EACCES || code == EPERM
        }

        /// The POSIX code under a Foundation file error, or 0 when it carries none.
        private static func posixCode(of error: any Error) -> Int32 {
            let error = error as NSError
            if error.domain == NSPOSIXErrorDomain { return Int32(error.code) }
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
                return Int32(underlying.code)
            }
            let permissionCodes = [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue]
            return error.domain == NSCocoaErrorDomain && permissionCodes.contains(error.code) ? EACCES : 0
        }
    }
#endif
