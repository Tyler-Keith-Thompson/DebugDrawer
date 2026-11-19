#if DEBUG
    import Foundation
    import os

    /// Where a resend of a captured request stands, which that request's detail shows. A resend
    /// that got its answer has no status: its own entry in the log is the result.
    enum NetworkReplayStatus: Equatable, Codable, Sendable {
        /// Sent, and waiting for the answer.
        case sending
        /// No answer came; the message says why.
        case failed(String)
    }

    /// Resends captured requests, marked as replays so the log links each to its original, and
    /// keeps where each resend stands. On the main actor, since the drawer reads the statuses as it
    /// draws; the sending itself happens off it.
    @MainActor
    final class NetworkReplayModel: ObservableObject {
        /// The model the plugin resends through: the app's default session with the plugin's URL
        /// protocol.
        static let shared = NetworkReplayModel(sender: _NetworkReplaySender())

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkReplayModel")

        /// Where the last resend of each captured request stands, by the captured request's id.
        @Published private(set) var statuses: [NetworkEntry.ID: NetworkReplayStatus] = [:]

        let sender: any NetworkReplaySender

        /// - Parameter sender: Sends the resent requests.
        init(sender: any NetworkReplaySender) {
            self.sender = sender
        }

        /// Sends `entry` again, unchanged. One whose body the log cut short isn't sent, and its
        /// status says why.
        func resend(_ entry: NetworkEntry) async {
            if let problem = NetworkReplayDraft.resendProblem(of: entry) {
                statuses[entry.id] = .failed(problem)
                return
            }
            guard let request = NetworkReplayDraft(entry).request else {
                statuses[entry.id] = .failed("The captured request can't be sent again: its URL or body isn't one a request can carry.")
                return
            }
            await resend(request, replaying: entry.id)
        }

        /// Sends `request`, marked as a replay of the captured request with id `original`, and
        /// returns once its answer has arrived or it failed.
        func resend(_ request: URLRequest, replaying original: NetworkEntry.ID) async {
            statuses[original] = .sending
            do {
                try await sender.send(request.markedAsReplay(of: original))
                statuses[original] = nil
            } catch is CancellationError {
                statuses[original] = nil
            } catch let error as URLError where error.code == .cancelled {
                statuses[original] = nil
            } catch {
                Self.logger.error("Network replay failed: \(error.localizedDescription, privacy: .public)")
                statuses[original] = .failed(error.localizedDescription)
            }
        }
    }
#endif
