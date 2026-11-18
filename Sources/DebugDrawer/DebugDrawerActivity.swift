/// Marks work as the drawer's own, so the plugins that record what the app does leave it out.
///
/// The Disk I/O plugin records the app's file calls; the drawer's own (the File Browser listing a
/// folder, a bug report being written, a plugin saving its settings) would bury them. A plugin
/// runs its file work with ``isDrawerWork`` bound to `true`:
///
/// ```swift
/// let names = try DebugDrawerActivity.$isDrawerWork.withValue(true) {
///     try FileManager.default.contentsOfDirectory(atPath: folder)
/// }
/// ```
///
/// The value is task-local: it holds for the operation and every task it creates, and in
/// synchronous code outside a task, for the current thread. Work the operation hands to another
/// thread (a dispatch queue, a callback) isn't covered; bind it there too.
///
/// The type exists in every build, so a plugin's code compiles unchanged in release, where nothing
/// records.
public enum DebugDrawerActivity {
    /// Whether the current task, or the current thread outside a task, runs the drawer's own work.
    @TaskLocal public static var isDrawerWork = false
}
