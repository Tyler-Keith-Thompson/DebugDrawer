#if DEBUG
    import DebugDrawer
    import SwiftUI

    public struct ConsolePlugin: DebugDrawerPlugin {
        public var title = "Console"
        public var category = "Logs & Network"
        public var icon = "terminal"

        public init() {}

        public var body: some View {
            ConsolePluginView()
        }

        /// How many lines the console holds.
        public var headerAccessory: some View {
            ConsoleHeaderAccessoryView()
        }
    }

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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Install the console capture plugin. Call once at app startup.
        /// Captures stdout, stderr, and os_log entries.
        ///
        /// - Parameter sessions: How many earlier launches' lines are kept on disk, in how many
        ///   bytes, and where; each line is written as it is captured, and the console shows the
        ///   earlier sessions under Previous. ``ConsoleSessionPersistence/off`` writes none.
        func installConsole(sessions: ConsoleSessionPersistence = .standard) {
            // Started before capture begins, so the first line is written too, and once a launch,
            // so a second install doesn't start a second session.
            if ConsoleLogStore.shared.recorder == nil {
                let recorder = ConsoleSessionRecorder(sessions)
                ConsoleLogStore.shared.persist(to: recorder)
                Task { await ConsoleSessionsModel.shared.start(recorder) }
            }
            ConsoleLogStore.shared.install()
            registerGlobal(ConsolePlugin())
        }
    }
#endif
