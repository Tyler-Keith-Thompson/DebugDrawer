#if DEBUG
    import Foundation
    import os

    /// The sessions earlier launches kept, on the main actor, for the drawer: listed, read and
    /// deleted through the recorder `installConsole()` starts.
    @MainActor
    final class ConsoleSessionsModel: ObservableObject {
        /// The model the plugin shows; it lists nothing until `installConsole()` starts it.
        static let shared = ConsoleSessionsModel()

        private static let logger = Logger(subsystem: "DebugDrawerConsolePlugin", category: "ConsoleSessionsModel")

        /// The sessions earlier launches kept, the newest first.
        @Published private(set) var sessions: [ConsoleSessionSummary] = []
        /// The session last asked for that couldn't be read, until another is read.
        @Published private(set) var unreadable: ConsoleSessionSummary?
        /// What writes the current session and reads the earlier ones; `nil` until started.
        private(set) var recorder: ConsoleSessionRecorder?

        init(recorder: ConsoleSessionRecorder? = nil) {
            self.recorder = recorder
        }

        /// Lists the sessions through `recorder` from now on, starting now.
        func start(_ recorder: ConsoleSessionRecorder) async {
            self.recorder = recorder
            await reload()
        }

        /// Lists the sessions again.
        func reload() async {
            sessions = await recorder?.previousSessions() ?? []
        }

        /// The session with `id`, read whole; `nil` when it is no longer kept or can't be read,
        /// which `unreadable` then names.
        func log(of id: ConsoleSessionSummary.ID) async -> ConsoleSessionLog? {
            guard let recorder, let summary = sessions.first(where: { $0.id == id }) else { return nil }
            do {
                let log = try await recorder.log(of: summary)
                unreadable = nil
                return log
            } catch {
                // Logged by the user's action, once per attempt, so it can't loop through the
                // Console's own capture.
                Self.logger.error("Console session not read: \(error.localizedDescription, privacy: .public)")
                unreadable = summary
                return nil
            }
        }

        /// Deletes the sessions with `ids`, then lists what is left.
        func delete(_ ids: [ConsoleSessionSummary.ID]) async {
            await recorder?.delete(ids)
            await reload()
        }
    }
#endif
