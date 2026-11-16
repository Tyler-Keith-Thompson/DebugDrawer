#if DEBUG
    import DebugDrawer
    import Foundation

    extension BackgroundTasksPlugin: DebugDrawerReportContributor {
        /// Adds `background-tasks.txt`: the background modes, the permitted identifiers and the
        /// pending requests, as last read.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(declaration: model.declaration, pending: model.pending, to: &report)
        }

        /// Adds the state as `background-tasks.txt`. Nothing is redacted: identifiers are the
        /// app's own names for its tasks. Dates are in UTC.
        static func contribute(declaration: BackgroundTaskDeclaration, pending: PendingRequestsState, to report: inout DebugDrawerReport) {
            report.add(text: text(declaration: declaration, pending: pending), named: "background-tasks.txt")
        }

        static func text(declaration: BackgroundTaskDeclaration, pending: PendingRequestsState) -> String {
            let modes = declaration.kinds.isEmpty ? "none" : declaration.kinds.map(\.backgroundMode).joined(separator: ", ")
            let identifiers = ["Permitted identifiers (\(declaration.identifiers.count)):"] + declaration.identifiers.map { "  \($0.id)" }
            let requests = switch pending {
            case .loading: ["Pending requests: not read yet"]
            case let .loaded(requests): ["Pending requests (\(requests.count)):"] + requests.flatMap(\.reportLines)
            }
            return (["Background modes: \(modes)"] + identifiers + requests).joined(separator: "\n")
        }
    }

    extension BackgroundTaskRequest {
        /// Its identifier, then its kind with its conditions and its earliest begin date, indented.
        fileprivate var reportLines: [String] {
            let earliest = earliestBeginDate.map { $0.formatted(.iso8601) } ?? "none"
            return ["  \(id)", "    kind: \(kind.summary)", "    earliest begin: \(earliest)"]
        }
    }
#endif
