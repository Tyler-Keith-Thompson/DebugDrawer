import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that captures and registers nothing.

public struct ConsolePlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "ConsolePlugin"
    }

    public var title = "Console"
    public var category = "Logs & Network"
    public var icon = "terminal"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one.
        let model: ConsoleModel?

        /// The plugin over ``ConsoleModel/shared``, whose store `installConsole()` sets up.
        public init() {
            model = nil
        }

        /// - Parameter model: The model to show, in place of the shared one; its store gets the
        ///   captured lines while a drawer holding this plugin is the latest to have installed it.
        init(model: ConsoleModel) {
            self.model = model
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            ConsolePluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// How many lines the console holds.
    public var headerAccessory: some View {
        #if DEBUG
            ConsoleHeaderAccessoryView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Starts capture, if nothing has: the process's os_log entries and, on macOS, stdout and
    /// stderr. They go to this plugin's store (``ConsoleLogStore/shared`` for the plugin
    /// `installConsole()` registers) until another drawer installs the Console plugin, and again
    /// once that one removes it. Release builds capture nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).store.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Hands capture back to the drawer that installed the Console plugin before `drawer`, and
    /// drops the lines of this plugin's store once nothing captures into it. Once no drawer has
    /// the plugin and the app hasn't called ``ConsoleLogStore/install()``, stops capture: stdout
    /// and stderr write to where they did before and the console's os_log driver is removed.
    /// Earlier sessions on disk and the mutes stay.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).store.uninstall(from: ObjectIdentifier(drawer))
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
            // The plugin's install starts capture.
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
    /// The Console plugin's header accessory, drawn from the model's snapshots as the plugin's body
    /// is.
    struct ConsoleHeaderAccessoryView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            ConsoleHeaderSummary(lineCount: transport.snapshot.log.lines.count)
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
