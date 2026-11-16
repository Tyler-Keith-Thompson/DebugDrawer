// `bazel build //...` also compiles this library for the Mac, where BackgroundTasks' types are
// unavailable, so that build leaves this out.
#if canImport(BackgroundTasks) && !os(macOS)
    import BackgroundTasks
    import os

    /// The app's own background tasks, as an app registers them: one launch handler per identifier
    /// its Info.plist permits, before it finishes launching. Each handler logs, so the Console
    /// plugin shows a launch the debugger simulated, and completes at once.
    enum ExampleBackgroundTasks {
        static let refreshIdentifier = "com.debugdrawer.example.refresh"
        static let cleanupIdentifier = "com.debugdrawer.example.cleanup"
        private static let logger = Logger(subsystem: "ExampleApp_iOS", category: "ExampleBackgroundTasks")

        /// Registers a handler for each permitted identifier. Call it from
        /// `application(_:didFinishLaunchingWithOptions:)`: the scheduler refuses one registered later.
        static func register() {
            for identifier in [refreshIdentifier, cleanupIdentifier] {
                BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                    logger.info("Background task \(task.identifier, privacy: .public) launched")
                    task.expirationHandler = {
                        logger.info("Background task \(task.identifier, privacy: .public) expired")
                    }
                    task.setTaskCompleted(success: true)
                }
            }
        }
    }
#endif
