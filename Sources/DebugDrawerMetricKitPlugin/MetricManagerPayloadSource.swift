#if DEBUG && canImport(MetricKit)
    import MetricKit

    /// MetricKit's payloads, as an `MXMetricManager` subscriber. MetricKit delivers to every
    /// subscriber, so this one coexists with the app's own and with Crash Reports' and Hangs'.
    final class MetricManagerPayloadSource: NSObject, MetricKitPayloadSource, MXMetricManagerSubscriber {
        private var receive: (@MainActor ([ReceivedMetricKitPayload]) -> Void)?

        func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void) {
            let isSubscribed = self.receive != nil
            self.receive = receive
            let manager = MXMetricManager.shared
            // The past payloads repeat ones delivered before; the store keeps each once.
            receive(manager.pastPayloads.map(\.received) + manager.pastDiagnosticPayloads.map(\.received))
            if !isSubscribed {
                manager.add(self)
            }
        }

        /// MetricKit calls this on a queue of its own.
        nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
            deliver(payloads.map(\.received))
        }

        /// MetricKit calls this on a queue of its own.
        nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
            deliver(payloads.map(\.received))
        }

        private nonisolated func deliver(_ payloads: [ReceivedMetricKitPayload]) {
            guard !payloads.isEmpty else { return }
            Task { @MainActor in
                self.receive?(payloads)
            }
        }
    }

    extension MXMetricPayload {
        fileprivate var received: ReceivedMetricKitPayload {
            ReceivedMetricKitPayload(kind: .metrics, json: jsonRepresentation(), begin: timeStampBegin, end: timeStampEnd)
        }
    }

    extension MXDiagnosticPayload {
        fileprivate var received: ReceivedMetricKitPayload {
            ReceivedMetricKitPayload(kind: .diagnostics, json: jsonRepresentation(), begin: timeStampBegin, end: timeStampEnd)
        }
    }
#endif
