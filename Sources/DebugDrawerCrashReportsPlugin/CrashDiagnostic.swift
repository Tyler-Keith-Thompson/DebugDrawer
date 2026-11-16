#if DEBUG
    import Foundation

    /// A crash the system reported through MetricKit: an `MXCrashDiagnostic`'s
    /// `jsonRepresentation()` and the end of the period its payload covers.
    struct CrashDiagnostic: Equatable, Sendable {
        let json: Data
        let date: Date
    }

    /// Delivers the crash diagnostics the system reports, as they arrive: MetricKit's come on a
    /// later launch, often a day after the crash.
    @MainActor
    protocol CrashDiagnosticSource: AnyObject {
        /// Starts delivering diagnostics to `receive`, on the main actor.
        func subscribe(_ receive: @escaping @MainActor ([CrashDiagnostic]) -> Void)
    }

    extension CrashDiagnostic {
        /// The report the diagnostic describes, or `nil` when its JSON isn't a crash diagnostic.
        ///
        /// The title is the signal's name, else the Mach exception type; the reason is the
        /// Objective-C exception's message, else the termination reason; the frames are the
        /// crashed thread's, each its binary, offset and address.
        func report(id: UUID) -> CrashReport? {
            guard let diagnostic = try? JSONDecoder().decode(MetricKitCrash.self, from: json) else { return nil }
            let metadata = diagnostic.diagnosticMetaData
            let title = metadata?.signal.map { CrashFile.describe(signal: Int32(truncatingIfNeeded: $0)).name }
                ?? metadata?.exceptionType.map { "Exception type \($0)" }
                ?? "Crash"
            let version = metadata?.appVersion.map { version in
                metadata?.appBuildVersion.map { "\(version) (\($0))" } ?? version
            }
            let stacks = diagnostic.callStackTree?.callStacks ?? []
            let crashed = stacks.first { $0.threadAttributed == true } ?? stacks.first
            return CrashReport(
                id: id,
                date: date,
                title: title,
                reason: metadata?.objectiveCexceptionReason?.composedMessage ?? metadata?.terminationReason,
                appVersion: version,
                frames: crashed?.callStackRootFrames.first?.flattened.enumerated().map { $1.line(index: $0) } ?? [],
                source: .metricKit,
                isSeen: false
            )
        }
    }

    /// The parts of `MXCrashDiagnostic.jsonRepresentation()` the report uses; every field is
    /// optional, as MetricKit leaves out what it doesn't know.
    private struct MetricKitCrash: Decodable {
        struct Metadata: Decodable {
            var appVersion: String?
            var appBuildVersion: String?
            var signal: Int?
            var exceptionType: Int?
            var terminationReason: String?
            var objectiveCexceptionReason: MetricKitExceptionReason?
        }

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

        var diagnosticMetaData: Metadata?
        var callStackTree: Tree?
    }

    /// The Objective-C exception MetricKit names for a crash it caused.
    private struct MetricKitExceptionReason: Decodable {
        var composedMessage: String?
    }
#endif
