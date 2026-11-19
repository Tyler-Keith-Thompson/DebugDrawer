#if DEBUG && canImport(MetricKit)
    import MetricKit

    /// The hang diagnostics MetricKit delivers, as an `MXMetricManager` subscriber.
    final class MetricKitHangDiagnosticSource: NSObject, HangDiagnosticSource, MXMetricManagerSubscriber {
        private var receive: (@MainActor ([HangDiagnostic]) -> Void)?

        func subscribe(_ receive: @escaping @MainActor ([HangDiagnostic]) -> Void) {
            let isSubscribed = self.receive != nil
            self.receive = receive
            if !isSubscribed {
                MXMetricManager.shared.add(self)
            }
        }

        func unsubscribe() {
            guard receive != nil else { return }
            receive = nil
            MXMetricManager.shared.remove(self)
        }

        /// MetricKit calls this on a queue of its own.
        nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
            let diagnostics = payloads.flatMap { payload in
                (payload.hangDiagnostics ?? []).map { hang in
                    let seconds = hang.hangDuration.converted(to: .seconds).value
                    return HangDiagnostic(json: hang.jsonRepresentation(), duration: .seconds(seconds), date: payload.timeStampEnd)
                }
            }
            guard !diagnostics.isEmpty else { return }
            Task { @MainActor in
                self.receive?(diagnostics)
            }
        }
    }
#endif
