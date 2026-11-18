import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that captures and registers nothing.

public struct ConsolePlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "ConsolePlugin"
    }

    public var title = "Console"
    public var category = "Logs & Network"
    public var icon = "terminal"

    public init() {}

    public var body: some View {
        #if DEBUG
            ConsolePluginView()
        #else
            EmptyView()
        #endif
    }

    /// How many lines the console holds.
    public var headerAccessory: some View {
        #if DEBUG
            ConsoleHeaderAccessoryView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Installs the Console plugin. Call it once, at startup. It captures the process's os_log
    /// entries, the lines sent to ``ConsoleLogSink`` and, on macOS, stdout and stderr.
    ///
    /// Apple's frameworks log debug and info lines (subsystems starting with `com.apple.`) fast
    /// enough to push the app's own lines out of the console within seconds, so the console
    /// leaves them out unless `includeSystemDebugLogs` is `true`. Their notice, error and fault
    /// lines, and every line of the app's own, are always kept.
    ///
    /// - Parameters:
    ///   - sessions: How many earlier launches' lines are kept on disk, in how many bytes, and
    ///     where; each line is written as it is captured, and the console shows the earlier
    ///     sessions under Previous. ``ConsoleSessionPersistence/off`` writes none.
    ///   - includeSystemDebugLogs: Whether the console keeps the debug and info lines of Apple's
    ///     subsystems too; `false` by default.
    func installConsole(sessions: ConsoleSessionPersistence = .standard, includeSystemDebugLogs: Bool = false) {
        #if DEBUG
            ConsoleLogStore.shared.ingestFilter.includesSystemDebugLogs = includeSystemDebugLogs
            // Started before capture begins, so the first line is written too, and once a launch,
            // so a second install doesn't start a second session.
            if ConsoleLogStore.shared.recorder == nil {
                let recorder = ConsoleSessionRecorder(sessions, ingestFilter: ConsoleLogStore.shared.ingestFilter)
                ConsoleLogStore.shared.persist(to: recorder)
                Task { await ConsoleSessionsModel.shared.start(recorder) }
            }
            ConsoleLogStore.shared.install()
            registerGlobal(ConsolePlugin())
        #endif
    }

    /// Installs the Console plugin without Apple subsystems' debug and info lines.
    ///
    /// Calls resolve to ``installConsole(sessions:includeSystemDebugLogs:)``, which takes the
    /// same arguments.
    ///
    /// - Parameter sessions: How many earlier launches' lines are kept on disk, in how many
    ///   bytes, and where.
    @available(*, deprecated, message: "Use installConsole(sessions:includeSystemDebugLogs:)")
    @_disfavoredOverload
    func installConsole(sessions: ConsoleSessionPersistence = .standard) {
        installConsole(sessions: sessions, includeSystemDebugLogs: false)
    }
}

#if DEBUG
    /// The Console plugin's header accessory, read from the shared store as the plugin's body
    /// reads it.
    struct ConsoleHeaderAccessoryView: View {
        @ObservedObject private var store = ConsoleLogStore.shared

        var body: some View {
            ConsoleHeaderSummary(lineCount: store.lines.count)
        }
    }

    /// How many lines the console holds ("1,204 lines").
    struct ConsoleHeaderSummary: View {
        let lineCount: Int

        /// The count as the header shows it.
        var text: String {
            lineCount == 1 ? "1 line" : "\(lineCount.formatted()) lines"
        }

        var body: some View {
            Text(text)
        }
    }

#endif
