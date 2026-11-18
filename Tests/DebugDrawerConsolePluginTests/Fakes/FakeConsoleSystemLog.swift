#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import os

    /// A system log that answers every read with `outcome`, and keeps what each read asked for.
    final class FakeConsoleSystemLog: ConsoleSystemLog {
        struct Read: Equatable {
            var processIdentifier: Int32
            var since: Date
        }

        private let outcome: ConsoleEarlierProcess
        private let readsMade = OSAllocatedUnfairLock<[Read]>(initialState: [])

        init(_ outcome: ConsoleEarlierProcess) {
            self.outcome = outcome
        }

        /// The reads made, oldest first.
        var reads: [Read] {
            readsMade.withLock(\.self)
        }

        func lines(loggedBy processIdentifier: Int32, since date: Date) -> ConsoleEarlierProcess {
            readsMade.withLock { $0.append(Read(processIdentifier: processIdentifier, since: date)) }
            return outcome
        }
    }
#endif
