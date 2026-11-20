import Foundation
#if os(macOS)
    import Security
#endif

// Where the example's production host (Example/Receiver) and its sidecar (Example/Sidecar) meet:
// the `DebugDrawer` folder of the app group they share, which every store transport, the receiver
// and the sidecar kit's app list take as the group's store.
//
// iOS: the group is `group.com.debugdrawer.example`, which the simulator gives both apps from their
// entitlements without a provisioning profile.
//
// macOS: a group named `group.` needs a provisioning profile there, and a group the system can't
// tie to the app's signature makes macOS ask the person whether the app may "access data from
// other apps". So `just run sidecar macOS` signs both apps with the Keychain's Apple Development
// identity and the team-prefixed group `<team ID>.com.debugdrawer.example`
// (scripts/sign_example.py --app-group), and each app reads the group from its own entitlements.
// Signed ad hoc (no identity, or DEBUGDRAWER_SIGN_IDENTITY=-), neither app has a group, and both,
// which aren't sandboxed, share a folder in the user's Caches instead: the same store, without the
// protection a group container gives, which only an example may settle for.

/// Where the example host serves its sidecar and the example sidecar reads it.
public enum ExampleSidecarStore {
    /// The store's directory: the group's `DebugDrawer` folder, or, on a Mac whose apps were
    /// signed without a group, the shared folder in Caches.
    public static var directory: URL {
        switch location {
        case let .appGroup(_, container): container.appending(path: "DebugDrawer", directoryHint: .isDirectory)
        case let .sharedFolder(folder): folder
        }
    }

    /// Where the store is, in a line each app shows, so a run says which of the two it got.
    public static var summary: String {
        switch location {
        case let .appGroup(identifier, _): "App group \(identifier)"
        case .sharedFolder: "Shared folder in Caches (signed without an app group)"
        }
    }

    /// The two places the store can be.
    private enum Location {
        case appGroup(identifier: String, container: URL)
        case sharedFolder(URL)
    }

    private static var location: Location {
        if let identifier = groupIdentifier,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return .appGroup(identifier: identifier, container: container)
        }
        return .sharedFolder(URL.cachesDirectory.appending(path: "com.debugdrawer.example/DebugDrawer", directoryHint: .isDirectory))
    }

    /// The group the app was signed with: on the Mac, the first of its own
    /// `com.apple.security.application-groups`, which `just run sidecar macOS` prefixes with the
    /// signing team; elsewhere the examples' group.
    private static var groupIdentifier: String? {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                  let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String]
            else { return nil }
            return groups.first
        #else
            "group.com.debugdrawer.example"
        #endif
    }
}
