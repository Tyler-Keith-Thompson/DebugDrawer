#if DEBUG
    /// The drawer's latest Schedule: none yet, one on its way, or one the scheduler refused. One
    /// it accepted shows as the pending request it made.
    enum ScheduleState: Equatable, Sendable {
        case idle
        case scheduling(identifier: String, kind: BackgroundTaskKind)
        case failed(identifier: String, kind: BackgroundTaskKind, failure: BackgroundTaskSubmitFailure)

        /// The state as the row of `identifier` shows it: `idle` for every other row.
        func shown(for identifier: String) -> ScheduleState {
            switch self {
            case let .scheduling(scheduled, _), let .failed(scheduled, _, _):
                scheduled == identifier ? self : .idle
            case .idle:
                .idle
            }
        }
    }
#endif
