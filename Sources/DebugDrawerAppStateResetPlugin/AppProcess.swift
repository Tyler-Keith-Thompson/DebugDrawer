#if DEBUG
    import Foundation
    #if os(macOS)
        import AppKit
    #endif

    /// How the app starts over after a reset.
    enum RestartStyle: Hashable, Sendable {
        /// It launches a new instance of itself and quits: macOS.
        case relaunch
        /// It quits, to be opened again by hand: iOS, tvOS, visionOS and Mac Catalyst, where an
        /// app can't launch itself.
        case quit
    }

    /// Why the app couldn't relaunch.
    struct RelaunchFailure: Error, Hashable, Sendable {
        let message: String
    }

    /// The running process, ended after a reset so the app starts as a fresh install would.
    @MainActor
    protocol AppProcess {
        /// How this platform starts over.
        var restartStyle: RestartStyle { get }
        /// Relaunches or quits. It returns only when a relaunch couldn't start.
        ///
        /// - Throws: `RelaunchFailure` when the new instance couldn't be launched; the app keeps
        ///   running.
        func restart() async throws(RelaunchFailure)
    }

    /// The app's own process.
    struct _AppProcess: AppProcess {
        var restartStyle: RestartStyle {
            #if os(macOS)
                .relaunch
            #else
                // Mac Catalyst takes this branch too: UIKit has no way to launch an app, the
                // running one included.
                .quit
            #endif
        }

        func restart() async throws(RelaunchFailure) {
            #if os(macOS)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                } catch {
                    throw RelaunchFailure(message: error.localizedDescription)
                }
                NSApp.terminate(nil)
            #else
                // `exit` is public API, but App Review rejects an app that quits itself. The
                // plugin exists in debug builds only, which never reach review, and an app can't
                // relaunch itself here; the drawer says to open it again.
                exit(EXIT_SUCCESS)
            #endif
        }
    }
#endif
