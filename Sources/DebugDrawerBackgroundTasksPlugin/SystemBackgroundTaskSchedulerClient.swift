// BackgroundTasks' module exists in the macOS SDK, but every type in it is unavailable there, so
// this file builds for iOS and Mac Catalyst (where `os(macOS)` is false and the scheduler is
// available) and nowhere else.
#if DEBUG && canImport(BackgroundTasks) && !os(macOS)
    import BackgroundTasks
    import Foundation

    /// The shared `BGTaskScheduler`. Every request it hands back is mapped into the plugin's own
    /// `BackgroundTaskRequest` here, so the rest of the plugin imports nothing of the framework
    /// and its views and model build and are tested on the Mac.
    struct SystemBackgroundTaskSchedulerClient: BackgroundTaskSchedulerClient {
        func pendingTaskRequests() async -> [BackgroundTaskRequest] {
            // The handler may run on a background thread, so the framework's requests, which
            // aren't Sendable, are mapped there and only the plugin's values cross back.
            await withCheckedContinuation { continuation in
                BGTaskScheduler.shared.getPendingTaskRequests { requests in
                    continuation.resume(returning: requests.map(BackgroundTaskRequest.init))
                }
            }
        }

        func submit(identifier: String, kind: BackgroundTaskKind, earliestBeginDate: Date) async throws(BackgroundTaskSubmitFailure) {
            try await Self.submit(identifier: identifier, kind: kind, earliestBeginDate: earliestBeginDate)
        }

        func cancel(taskRequestWithIdentifier identifier: String) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }

        func cancelAllTaskRequests() {
            BGTaskScheduler.shared.cancelAllTaskRequests()
        }

        /// Builds and submits the request off the main actor: submitting can block while the
        /// scheduler checks the request, and Apple asks that it not be done on the main thread.
        @concurrent
        private static func submit(identifier: String, kind: BackgroundTaskKind, earliestBeginDate: Date) async throws(BackgroundTaskSubmitFailure) {
            let request: BGTaskRequest = switch kind {
            case .appRefresh: BGAppRefreshTaskRequest(identifier: identifier)
            case .processing: BGProcessingTaskRequest(identifier: identifier)
            }
            request.earliestBeginDate = earliestBeginDate
            do {
                if #available(iOS 27.0, *) {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } else {
                    try BGTaskScheduler.shared.submit(request)
                }
            } catch let error as BGTaskScheduler.Error {
                throw BackgroundTaskSubmitFailure(schedulerErrorCode: error.code.rawValue, message: error.localizedDescription)
            } catch {
                throw .other(message: error.localizedDescription)
            }
        }
    }

    extension BackgroundTaskRequest {
        fileprivate init(_ request: BGTaskRequest) {
            let kind: Kind = switch request {
            case let processing as BGProcessingTaskRequest:
                .processing(
                    requiresNetworkConnectivity: processing.requiresNetworkConnectivity,
                    requiresExternalPower: processing.requiresExternalPower
                )
            case is BGAppRefreshTaskRequest: .appRefresh
            default: .other(className: String(describing: type(of: request)))
            }
            self.init(id: request.identifier, earliestBeginDate: request.earliestBeginDate, kind: kind)
        }
    }
#endif
