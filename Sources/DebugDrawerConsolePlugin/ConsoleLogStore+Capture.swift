#if DEBUG
    import Foundation

    // Capture of stdout, stderr and os_log, started by the first install and stopped by the last
    // uninstall (`ConsoleCapture`): the app's own install() counts as one, each drawer with the
    // Console plugin as another, and the latest of them gets the lines.
    extension ConsoleLogStore {
        /// Captures stdout and stderr (on macOS) and the process's os_log entries into this store
        /// until ``uninstall()``, whether or not a drawer has the Console plugin. The drawer needs
        /// no call: the plugin captures while a drawer has it. Calling it again does nothing.
        public func install() {
            ConsoleCapture.install(self, for: ObjectIdentifier(self))
        }

        /// Ends what ``install()`` began. Capture goes on while a drawer has the Console plugin;
        /// once nothing wants it, stdout and stderr write to where they did before, os_log entries
        /// are no longer read, and the captured lines are dropped. Calling it again does nothing.
        public func uninstall() {
            ConsoleCapture.uninstall(for: ObjectIdentifier(self))
        }

        /// Captures into this store while `drawer` holds the Console plugin and is the latest to
        /// have installed it; the first install starts capture.
        func install(in drawer: ObjectIdentifier) {
            ConsoleCapture.install(self, for: drawer)
        }

        /// Uncounts `drawer`; the install before it gets the lines again, and the last one stops
        /// capture.
        func uninstall(from drawer: ObjectIdentifier) {
            ConsoleCapture.uninstall(for: drawer)
        }
    }
#endif
