#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation

    /// A process the test chooses: its start, a footprint the test moves, its ID and arguments;
    /// counts the starts and footprints read.
    final class FakeProcessMetricsSource: ProcessMetricsSource {
        var processStart: ProcessStart?
        var footprint: Double
        let processIdentifier: Int32
        let argumentCount: Int
        private(set) var startReads = 0
        private(set) var footprintReads = 0

        init(start: ProcessStart? = nil, footprintMB: Double = 0, processIdentifier: Int32 = 0, argumentCount: Int = 0) {
            processStart = start
            footprint = footprintMB
            self.processIdentifier = processIdentifier
            self.argumentCount = argumentCount
        }

        func start() -> ProcessStart? {
            startReads += 1
            return processStart
        }

        func footprintMB() -> Double {
            footprintReads += 1
            return footprint
        }
    }
#endif
