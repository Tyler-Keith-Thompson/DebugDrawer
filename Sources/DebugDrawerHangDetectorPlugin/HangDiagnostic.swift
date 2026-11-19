#if DEBUG
    import Foundation

    /// A hang the system reported through MetricKit: an `MXHangDiagnostic`'s
    /// `jsonRepresentation()`, its `hangDuration`, and the end of the period its payload covers.
    struct HangDiagnostic: Equatable, Sendable {
        let json: Data
        let duration: Duration
        let date: Date
    }

    /// Delivers the hang diagnostics the system reports, as they arrive: MetricKit's come on a
    /// later launch, up to a day after the hang.
    @MainActor
    protocol HangDiagnosticSource: AnyObject {
        /// Starts delivering diagnostics to `receive`, on the main actor, in place of the one given
        /// before.
        func subscribe(_ receive: @escaping @MainActor ([HangDiagnostic]) -> Void)
        /// Stops delivering diagnostics until the next ``subscribe(_:)``.
        func unsubscribe()
    }

    extension HangDiagnostic {
        /// The hang the diagnostic describes, or `nil` when its JSON isn't a diagnostic with a
        /// call stack tree.
        ///
        /// The frames are the main thread's (the one MetricKit attributes the hang to, else its
        /// first), each its binary, address and offset.
        func event(id: UUID) -> HangEvent? {
            guard let diagnostic = try? JSONDecoder().decode(MetricKitHang.self, from: json) else { return nil }
            let stacks = diagnostic.callStackTree.callStacks
            let attributed = stacks.first { $0.threadAttributed == true } ?? stacks.first
            return HangEvent(
                id: id,
                date: date,
                duration: duration,
                frames: attributed?.callStackRootFrames.first?.flattened.enumerated().map { $1.line(index: $0) } ?? [],
                source: .metricKit,
                isSeen: false
            )
        }
    }

    // The JSON's shape, copied from the crash plugin's MetricKit reading (DebugDrawerCrashReportsPlugin's
    // CrashDiagnostic) rather than shared, as plugins don't depend on each other.

    /// The parts of `MXHangDiagnostic.jsonRepresentation()` the event uses; every frame field is
    /// optional, as MetricKit leaves out what it doesn't know.
    private struct MetricKitHang: Decodable {
        struct Tree: Decodable {
            var callStacks: [Stack]
        }

        struct Stack: Decodable {
            var threadAttributed: Bool?
            var callStackRootFrames: [Frame]
        }

        /// A frame; its caller is its first sub-frame.
        struct Frame: Decodable {
            var binaryName: String?
            var offsetIntoBinaryTextSegment: Int?
            var address: Int?
            var subFrames: [Frame]?

            /// This frame and its callers, innermost first.
            var flattened: [Frame] {
                [self] + (subFrames?.first?.flattened ?? [])
            }

            func line(index: Int) -> String {
                let address = address.map { "0x" + String($0, radix: 16) } ?? "?"
                let offset = offsetIntoBinaryTextSegment.map { " + \($0)" } ?? ""
                return "\(index) \(binaryName ?? "???") \(address)\(offset)"
            }
        }

        var callStackTree: Tree
    }
#endif
