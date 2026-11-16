#if DEBUG
    /// What the drawer knows of the scheduler's pending requests.
    enum PendingRequestsState: Equatable, Sendable {
        /// Not read yet.
        case loading
        /// The requests, as last read or as the drawer's own cancellations left them.
        case loaded([BackgroundTaskRequest])
    }
#endif
