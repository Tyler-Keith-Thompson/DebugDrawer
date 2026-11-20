import Foundation
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

// Bringing the app a sidecar drives to the foreground, so it performs what the sidecar left in the
// store (a receiver performs waiting commands as its app comes forward). On the Mac, Launch Services
// opens an app by its bundle identifier, which the presence file already gives, so no URL scheme is
// needed there. iOS offers apps no public way to open another app but a URL it claims, so there the
// host declares one (a scenario launcher's `launchURL`). Rejected: opening by bundle identifier on
// iOS (only private API does it, which App Review rejects) and a URL the kit makes up from the
// bundle identifier (no app claims it unless its host adds it, which is the same declaration).

#if DEBUG
    extension DebugDrawerSidecarApp {
        /// Brings the app to the foreground.
        ///
        /// On the Mac it opens the app by its bundle identifier, launching it if it isn't running,
        /// and opens `url` only when Launch Services finds no app with that identifier. On iOS and
        /// iPadOS it opens `url`, a URL of the app's own scheme, the only way one app can bring
        /// another forward there.
        ///
        /// - Parameter url: A URL the app claims (its `CFBundleURLTypes`), such as a scenario
        ///   launcher's `DebugDrawerScenarios.Snapshot.launchURL`, or `nil`.
        /// - Returns: Whether the system opened the app: `false` on iOS without `url`, or when no
        ///   app claims it.
        @MainActor
        @discardableResult
        public func open(url: URL?) async -> Bool {
            #if os(macOS)
                if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    do {
                        _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
                        return true
                    } catch {
                        return false
                    }
                }
                guard let url else { return false }
                return NSWorkspace.shared.open(url)
            #else
                guard let url else { return false }
                return await UIApplication.shared.open(url)
            #endif
        }
    }
#else
    // The release stand-in: a release build's kit lists no app, so there is none to open.

    extension DebugDrawerSidecarApp {
        /// Brings the app to the foreground; release builds open nothing.
        ///
        /// - Parameter url: A URL the app claims, or `nil`.
        /// - Returns: `false`.
        @MainActor
        @discardableResult
        public func open(url: URL?) async -> Bool {
            false
        }
    }
#endif
