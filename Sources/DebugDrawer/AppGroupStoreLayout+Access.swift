import DebugDrawerReceiver
import Foundation

// The store's layout lives in the receiver's module, which the drawer's transport error and
// `DirectoryAccess` can't reach (the receiver depends on nothing of the drawer's), so the drawer's
// servers and transports make the directories through this, failing closed with the drawer's own
// errors, while the receiver makes them with `create()`.

#if DEBUG
    extension AppGroupStoreLayout {
        /// Makes both directories, as either side may start first, and checks this process may
        /// read, write and search each: both sides write to both.
        ///
        /// - Throws: ``DebugDrawerTransportError/accessDenied`` when the system refuses, and
        ///   `otherwise` when the directories can't be made for any other reason.
        func create(otherwise: DebugDrawerTransportError) throws(DebugDrawerTransportError) {
            try DirectoryAccess.prepare(snapshots, need: .readWrite, otherwise: otherwise)
            try DirectoryAccess.prepare(commands, need: .readWrite, otherwise: otherwise)
        }
    }
#endif
