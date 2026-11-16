// Named for BGTaskScheduler's requests rather than `BackgroundTasks`, which would shadow Apple's
// module of that name in every file that imports both.

/// Background tasks in the debug drawer: the task identifiers the app's Info.plist permits, the
/// requests waiting in `BGTaskScheduler` with their kind and earliest begin date, each
/// cancellable, a request scheduled on demand, and the LLDB commands that make the system launch
/// a task, or expire it, at once.
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing and the plugin references nothing of BackgroundTasks.
public enum BackgroundTaskRequests {
    /// Adds the Background Tasks plugin: in debug builds on iOS, iPadOS and Mac Catalyst only.
    /// In release it does nothing, and on macOS, which has no `BGTaskScheduler`, it adds nothing.
    ///
    /// The plugin lists the identifiers in the main bundle's `BGTaskSchedulerPermittedIdentifiers`
    /// and the pending requests, read when installed, each time the app becomes active, after
    /// each of its own actions and on Refresh; nothing polls. It registers no launch handlers:
    /// those stay the app's, registered before it finishes launching, as `BGTaskScheduler`
    /// requires.
    ///
    /// Call it once at startup. Calling it again replaces the plugin with one that reads the
    /// Info.plist again.
    @MainActor
    public static func install() {
        #if DEBUG && canImport(BackgroundTasks) && !os(macOS)
            // Mac Catalyst takes this path too: `os(macOS)` is false there, and BGTaskScheduler
            // is available.
            BackgroundTaskRequestsInstallation.install(client: SystemBackgroundTaskSchedulerClient())
        #endif
    }
}
