#if DEBUG
    extension PermittedIdentifier {
        /// The LLDB command that makes the system launch this identifier's task now, as it would
        /// in the background, once a request for it is pending: typed at the debugger's prompt
        /// while the app is paused.
        ///
        /// The drawer only copies it: `_simulateLaunchForTaskWithIdentifier:` is private API,
        /// so only the debugger may call it.
        var simulateLaunchCommand: String {
            command(selector: "_simulateLaunchForTaskWithIdentifier:")
        }

        /// The LLDB command that makes the system expire this identifier's running task now,
        /// calling its expiration handler, as it would when background time runs out.
        var simulateExpirationCommand: String {
            command(selector: "_simulateExpirationForTaskWithIdentifier:")
        }

        private func command(selector: String) -> String {
            "e -l objc -- (void)[[BGTaskScheduler sharedScheduler] \(selector)@\"\(objectiveCEscaped)\"]"
        }

        /// The identifier as the body of an Objective-C string literal: a backslash or a quote
        /// in it is escaped, so the command still parses.
        private var objectiveCEscaped: String {
            id.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        }
    }
#endif
