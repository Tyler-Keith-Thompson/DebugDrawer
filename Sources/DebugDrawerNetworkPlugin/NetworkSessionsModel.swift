#if DEBUG
    import Foundation
    import os

    /// The sessions earlier launches kept, on the main actor, for the drawer: listed, read and
    /// deleted through the recorder `installNetwork()` starts.
    @MainActor
    final class NetworkSessionsModel: ObservableObject {
        /// The model the plugin shows; it lists nothing until `installNetwork()` starts it.
        static let shared = NetworkSessionsModel()

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkSessionsModel")

        /// The sessions earlier launches kept, the newest first.
        @Published private(set) var sessions: [NetworkSessionSummary] = []
        /// The session last asked for that couldn't be read, until another is read.
        @Published private(set) var unreadable: NetworkSessionSummary?
        /// What writes the current session and reads the earlier ones; `nil` until started.
        private(set) var recorder: NetworkSessionRecorder?

        init(recorder: NetworkSessionRecorder? = nil) {
            self.recorder = recorder
        }

        /// Lists the sessions through `recorder` from now on, starting now.
        func start(_ recorder: NetworkSessionRecorder) async {
            self.recorder = recorder
            await reload()
        }

        /// Lists the sessions again.
        func reload() async {
            sessions = await recorder?.previousSessions() ?? []
        }

        /// The session with `id`, read whole; `nil` when it is no longer kept or can't be read,
        /// which `unreadable` then names.
        func log(of id: NetworkSessionSummary.ID) async -> NetworkSessionLog? {
            guard let recorder, let summary = sessions.first(where: { $0.id == id }) else { return nil }
            do {
                let log = try await recorder.log(of: summary)
                unreadable = nil
                return log
            } catch {
                Self.logger.error("Network session not read: \(error.localizedDescription, privacy: .public)")
                unreadable = summary
                return nil
            }
        }

        /// Deletes the sessions with `ids`, then lists what is left.
        func delete(_ ids: [NetworkSessionSummary.ID]) async {
            await recorder?.delete(ids)
            await reload()
        }
    }
#endif
