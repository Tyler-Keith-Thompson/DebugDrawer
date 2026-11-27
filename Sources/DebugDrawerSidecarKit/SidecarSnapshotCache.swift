import CryptoKit
import DebugDrawer
import Foundation

// What a sidecar last read of each of an app's capabilities, kept so it can prepare commands while
// the app isn't running (DD-296): a production app's receiver serves a capability's snapshot only
// within a session and removes it from the shared store as the session ends and as it stops, so
// without a copy of its own the sidecar has nothing to edit before the app launches. The copy lives
// in the sidecar's own storage, never the shared store: the receiver removes its snapshots there on
// purpose, so nothing an earlier launch wrote stays readable to any app of the group, and the
// sidecar's Caches folder is the sidecar's alone.
//
//     <directory>/<store hash>-<percent-encoded bundle ID>/<percent-encoded plugin ID>.json
//
// One folder per app per group store (a hash of the app's directory of the store, so two groups'
// apps with one bundle ID, or two tests' temporary stores, never share one), one file per plugin:
// the snapshot's JSON as the plugin's own `Snapshot` type encodes it, written atomically, replaced
// as the app serves a newer one. Caches, as losing it costs only the preparing: the sidecar reads
// it again the next time the app serves it. A snapshot that no longer decodes (the app's types
// changed) is read as none.
//
// Rejected: keeping it in memory only (a sidecar relaunched before the app would have nothing).
//
// Built in release too, as `DebugDrawerSidecarPlugin` (which release builds keep) names it; a
// release connection makes none.

/// The snapshots a sidecar last read of one app's plugins, in the sidecar's own storage.
@MainActor
final class SidecarSnapshotCache {
    /// The folder of this app's snapshots.
    let directory: URL
    /// What each plugin's file holds, by plugin ID, so a snapshot that didn't change isn't
    /// written again.
    private var written: [String: Data] = [:]
    /// Reads each followed plugin transport's snapshots, until ``stopFollowing()``.
    private var following: [Task<Void, Never>] = []

    /// The snapshots of the app whose directory of the store is `appDirectory`, kept in
    /// `cacheDirectory`.
    init(appDirectory: URL, bundleIdentifier: String, in cacheDirectory: URL) {
        let digest = SHA256.hash(data: Data(appDirectory.standardizedFileURL.path.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        directory = cacheDirectory.appending(
            path: "\(hash)-\(AppGroupStoreLayout.fileName(bundleIdentifier))", directoryHint: .isDirectory
        )
    }

    deinit {
        for task in following {
            task.cancel()
        }
    }

    /// The sidecar's Caches folder for these snapshots: `DebugDrawer Sidecar Snapshots` in the
    /// user's caches directory, the sidecar's own container's when it is sandboxed.
    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return caches.appending(path: "DebugDrawer Sidecar Snapshots", directoryHint: .isDirectory)
    }

    /// The file holding `pluginID`'s snapshot.
    func file(for pluginID: String) -> URL {
        directory.appending(path: "\(AppGroupStoreLayout.fileName(pluginID)).json", directoryHint: .notDirectory)
    }

    /// The snapshot last read of `pluginID`, as `Snapshot`, or `nil` when none was read or it
    /// no longer decodes as that type.
    func snapshot<Snapshot: Decodable>(of pluginID: String, as type: Snapshot.Type) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(for: pluginID)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Keeps `snapshot` as `pluginID`'s, replacing the one kept before.
    func store(_ snapshot: some Encodable, of pluginID: String) {
        guard let data = try? JSONEncoder().encode(snapshot), written[pluginID] != data else { return }
        written[pluginID] = data
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file(for: pluginID), options: .atomic)
        } catch {
            // Preparing before launch is a convenience: the plugin goes on without it.
        }
    }

    /// Keeps each snapshot `transport` shows as `pluginID`'s, until ``stopFollowing()``: the
    /// current one before this returns, so a plugin hosted once can be prepared from then on.
    func follow<Snapshot, Command>(_ transport: DebugDrawerPluginTransport<Snapshot, Command>, as pluginID: String) {
        store(transport.snapshot, of: pluginID)
        let snapshots = transport.snapshots()
        following.append(
            Task { [weak self] in
                for await snapshot in snapshots {
                    self?.store(snapshot, of: pluginID)
                }
            }
        )
    }

    /// Stops keeping the followed transports' snapshots, letting go of them.
    func stopFollowing() {
        for task in following {
            task.cancel()
        }
        following = []
    }
}
