#if DEBUG
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation

    /// A scheduler the test fills: answers with the requests it holds, keeps each one submitted
    /// (or throws the failure the test sets), and records every cancellation.
    @MainActor
    final class FakeBackgroundTaskScheduler: BackgroundTaskSchedulerClient {
        struct Submission: Equatable {
            let identifier: String
            let kind: BackgroundTaskKind
            let earliestBeginDate: Date
        }

        var requests: [BackgroundTaskRequest]
        /// The failure each `submit` throws, if any.
        var submitFailure: BackgroundTaskSubmitFailure?
        private(set) var submissions: [Submission] = []
        private(set) var cancelled: [String] = []
        private(set) var cancelledAll = 0
        private(set) var reads = 0

        init(requests: [BackgroundTaskRequest] = []) {
            self.requests = requests
        }

        func pendingTaskRequests() async -> [BackgroundTaskRequest] {
            reads += 1
            return requests
        }

        func submit(identifier: String, kind: BackgroundTaskKind, earliestBeginDate: Date) async throws(BackgroundTaskSubmitFailure) {
            if let submitFailure { throw submitFailure }
            submissions.append(Submission(identifier: identifier, kind: kind, earliestBeginDate: earliestBeginDate))
            let requestKind: BackgroundTaskRequest.Kind = switch kind {
            case .appRefresh: .appRefresh
            case .processing: .processing(requiresNetworkConnectivity: false, requiresExternalPower: false)
            }
            requests.removeAll { $0.id == identifier }
            requests.append(BackgroundTaskRequest(id: identifier, earliestBeginDate: earliestBeginDate, kind: requestKind))
        }

        func cancel(taskRequestWithIdentifier identifier: String) {
            cancelled.append(identifier)
        }

        func cancelAllTaskRequests() {
            cancelledAll += 1
        }
    }

    /// A change source the test fires by hand.
    @MainActor
    final class FakeBackgroundTaskChangeSource: BackgroundTaskChangeSource {
        private var onChange: (@MainActor () async -> Void)?

        func observe(_ onChange: @escaping @MainActor () async -> Void) {
            self.onChange = onChange
        }

        /// Reports a change and waits for the plugin to read again.
        func change() async {
            await onChange?()
        }
    }
#endif
