import Foundation

// How a sidecar app learns which apps in its group serve it, the group's registry: each app that
// serves the store (a production app's `DebugDrawerReceiver`, a debug build's
// `DebugDrawerAppGroupStoreServer`) keeps a small file in its own directory of the store while it
// serves, and the sidecar kit watches the `apps/` directory and each app's directory in it
// (`DirectoryWatcher`) and lists one app per file. The file says who the app is and what it serves,
// nothing secret: its bundle ID, name, version and build, the IDs it serves, the protocol it speaks
// (its hello: major version, oldest version, capabilities) and when it last said so. It is written
// atomically (`AppGroupStoreLayout`), as the store's other files are, so a reader sees the old file
// or the new one.
//
//     <store>/apps/<percent-encoded bundle ID>/presence.json
//
// The app writes it as it starts serving, again as what it serves changes and as it comes back
// to the foreground (`lastSeen`), and removes it as it stops, so the list follows each app without
// either side polling. An app killed while serving can't remove its file: it stays, with the time
// the app was last seen, until the app serves again and replaces it.
//
// Rejected: a heartbeat rewritten on a timer (a clock where the app's own events already say when
// it changes, and writes the suspended app can't make anyway); a lock held on the file while
// serving, which the kernel releases when the process dies (iOS terminates a suspended app that
// holds a file lock in a shared container, 0xdead10cc); asking each listed process whether it is
// alive (another app's process is out of a sandboxed sidecar's reach); and the presence inside the
// sessions' snapshot (a debug build's ungated registry serves no sessions, and the sidecar would
// have to read every snapshot to list apps).

/// What an app serving the store says about itself in its directory of the store, as JSON.
package struct AppPresence: Codable, Equatable, Sendable {
    /// The schema this build writes. A reader reads the keys it knows of a newer one, as a later
    /// schema only adds keys. Schema 2 added `hello` and moved the file into the app's directory.
    package static let currentSchemaVersion = 2

    /// The schema the file is in.
    package var schemaVersion = AppPresence.currentSchemaVersion
    /// Who the app is.
    package var identity: Identity
    /// The IDs the app serves, sorted: its capabilities, and ``DebugDrawerSessions/pluginID`` when
    /// its commands act within sessions.
    package var capabilities: [String]
    /// When the app last wrote the file: as it started serving, as what it serves changed, or as
    /// it came to the foreground.
    package var lastSeen: Date
    /// The protocol the app's store speaks: its major version, the oldest it still speaks, and
    /// its capabilities, as each of its store files' writer says.
    package var hello: TransportHello

    package init(identity: Identity, capabilities: [String], lastSeen: Date, hello: TransportHello = .current) {
        self.identity = identity
        self.capabilities = capabilities.sorted()
        self.lastSeen = lastSeen
        self.hello = hello
    }

    /// Who an app is, as its bundle says.
    package struct Identity: Codable, Equatable, Sendable {
        /// The app's bundle identifier, which names its presence file.
        package var bundleIdentifier: String
        /// The name the app shows: `CFBundleDisplayName`, else `CFBundleName`, else the process's.
        package var displayName: String
        /// `CFBundleShortVersionString`, or empty.
        package var version: String
        /// `CFBundleVersion`, or empty.
        package var build: String

        package init(bundleIdentifier: String, displayName: String, version: String, build: String) {
            self.bundleIdentifier = bundleIdentifier
            self.displayName = displayName
            self.version = version
            self.build = build
        }

        /// The running app, as `bundle` describes it.
        package static func of(_ bundle: Bundle, process: ProcessInfo = .processInfo) -> Identity {
            let info = { (key: String) in bundle.object(forInfoDictionaryKey: key) as? String }
            return Identity(
                bundleIdentifier: bundle.bundleIdentifier ?? process.processName,
                displayName: info("CFBundleDisplayName") ?? info("CFBundleName") ?? process.processName,
                version: info("CFBundleShortVersionString") ?? "",
                build: info("CFBundleVersion") ?? ""
            )
        }
    }

    /// The file an app's presence is kept in, in its directory of the store, `appDirectory`.
    package static func file(inAppDirectory appDirectory: URL) -> URL {
        appDirectory.appending(path: "presence.json", directoryHint: .notDirectory)
    }

    /// The presence `data` holds, or `nil` when it isn't one.
    package static func decoded(from data: Data) -> AppPresence? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppPresence.self, from: data)
    }

    /// The presence as JSON, keys sorted and dates in ISO 8601, so the file reads in a capture.
    package func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // Strings, integers, a date and arrays of strings: encoding can't fail.
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// Keeps an app's presence file in a store while the app serves it.
@MainActor
package final class PresenceAnnouncement {
    private let file: URL
    private let layout: AppGroupStoreLayout
    private let now: () -> Date
    private var presence: AppPresence
    private var foregroundObservation: (any NSObjectProtocol)?

    /// Writes `identity`'s presence, serving `capabilities`, into its directory of the store,
    /// `directory`, and again each time the app comes to the foreground, until ``withdraw()``.
    ///
    /// - Parameters:
    ///   - directory: The app's directory of the store.
    ///   - identity: Who the app is.
    ///   - capabilities: The IDs the app serves.
    ///   - foreground: What the system posts as the app comes to the foreground.
    ///   - now: The time now; the system's by default.
    package init(
        directory: URL,
        identity: AppPresence.Identity,
        capabilities: [String],
        foreground: Notification.Name,
        now: @escaping () -> Date = Date.init
    ) {
        file = AppPresence.file(inAppDirectory: directory)
        layout = AppGroupStoreLayout(directory: directory)
        self.now = now
        presence = AppPresence(identity: identity, capabilities: capabilities, lastSeen: now())
        write()
        // No queue: the system posts it on the main thread.
        foregroundObservation = NotificationCenter.default.addObserver(forName: foreground, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.write()
            }
        }
    }

    /// Says the app now serves `capabilities`; writes nothing when that's what the file says.
    package func update(capabilities: [String]) {
        guard foregroundObservation != nil, capabilities.sorted() != presence.capabilities else { return }
        presence.capabilities = capabilities.sorted()
        write()
    }

    /// Removes the file: the app no longer serves the store. Later calls do nothing.
    package func withdraw() {
        guard let foregroundObservation else { return }
        NotificationCenter.default.removeObserver(foregroundObservation)
        self.foregroundObservation = nil
        try? FileManager.default.removeItem(at: file)
    }

    private func write() {
        presence.lastSeen = now()
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try layout.write(presence.encoded(), to: file)
        } catch {
            // Listing is a convenience for the sidecar: serving goes on without it.
        }
    }
}
