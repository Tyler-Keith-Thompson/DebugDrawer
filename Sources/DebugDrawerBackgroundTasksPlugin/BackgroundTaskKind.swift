#if DEBUG
    /// A kind of request the drawer schedules: the two that `BGTaskScheduler` launches in the
    /// background.
    enum BackgroundTaskKind: CaseIterable, Hashable, Sendable {
        /// `BGAppRefreshTaskRequest`: a short launch to fetch fresh content.
        case appRefresh
        /// `BGProcessingTaskRequest`: a launch of minutes, for deferrable work.
        case processing

        var title: String {
            switch self {
            case .appRefresh: "App Refresh"
            case .processing: "Processing"
            }
        }

        /// The `UIBackgroundModes` entry the system needs before it runs this kind.
        var backgroundMode: String {
            switch self {
            case .appRefresh: "fetch"
            case .processing: "processing"
            }
        }
    }
#endif
