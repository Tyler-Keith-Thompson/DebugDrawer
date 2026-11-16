#if DEBUG && canImport(MetricKit)
    import MetricKit

    /// The crash diagnostics MetricKit delivers, as an `MXMetricManager` subscriber.
    final class MetricKitCrashDiagnosticSource: NSObject, CrashDiagnosticSource, MXMetricManagerSubscriber {
        private var receive: (@MainActor ([CrashDiagnostic]) -> Void)?

        func subscribe(_ receive: @escaping @MainActor ([CrashDiagnostic]) -> Void) {
            self.receive = receive
            MXMetricManager.shared.add(self)
        }

        /// MetricKit calls this on a queue of its own.
        nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
            let diagnostics = payloads.flatMap { payload in
                (payload.crashDiagnostics ?? []).map { CrashDiagnostic(json: $0.jsonRepresentation(), date: payload.timeStampEnd) }
            }
            guard !diagnostics.isEmpty else { return }
            Task { @MainActor in
                self.receive?(diagnostics)
            }
        }
    }
#endif
