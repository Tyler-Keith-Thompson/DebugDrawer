#if DEBUG
    import Foundation

    /// A request waiting in `BGTaskScheduler`, mapped from the framework's request.
    struct BackgroundTaskRequest: Identifiable, Hashable, Sendable {
        /// What kind of launch the request asks for.
        enum Kind: Hashable, Sendable {
            /// `BGAppRefreshTaskRequest`.
            case appRefresh
            /// `BGProcessingTaskRequest`, with the conditions it waits for.
            case processing(requiresNetworkConnectivity: Bool, requiresExternalPower: Bool)
            /// A request class the drawer doesn't know, by its name.
            case other(className: String)
        }

        /// The task identifier; the scheduler holds one request per identifier.
        let id: String
        /// The earliest the system may launch the task; `nil` for no delay.
        let earliestBeginDate: Date?
        let kind: Kind
    }

    extension BackgroundTaskRequest.Kind {
        /// The kind in words ("App Refresh"), or the class name.
        var title: String {
            switch self {
            case .appRefresh: BackgroundTaskKind.appRefresh.title
            case .processing: BackgroundTaskKind.processing.title
            case let .other(className): className
            }
        }

        /// The conditions a processing request waits for, in words; empty for any other kind.
        var requirements: [String] {
            guard case let .processing(network, power) = self else { return [] }
            return (network ? ["Needs network"] : []) + (power ? ["Needs external power"] : [])
        }

        /// The kind and its conditions on one line ("Processing · Needs network").
        var summary: String {
            ([title] + requirements).joined(separator: " · ")
        }

        /// An SF Symbol for the kind.
        var systemImage: String {
            switch self {
            case .appRefresh: "arrow.clockwise"
            case .processing: "gearshape.2"
            case .other: "questionmark.square.dashed"
            }
        }
    }
#endif
