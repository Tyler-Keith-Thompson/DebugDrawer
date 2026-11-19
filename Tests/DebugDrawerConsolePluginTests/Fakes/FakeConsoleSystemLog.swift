#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import os

    /// A system log that answers each read with the next of its outcomes, the last one again once
    /// they run out, and keeps what each read asked for.
    final class FakeConsoleSystemLog: ConsoleSystemLog {
        struct Read: Equatable {
            var processIdentifier: Int32
            var since: Date
        }

        private let outcomes: [ConsoleEarlierProcess]
        private let readsMade = OSAllocatedUnfairLock<[Read]>(initialState: [])

        /// A log that answers every read with `outcome`.
        convenience init(_ outcome: ConsoleEarlierProcess) {
            self.init(reads: [outcome])
        }

        /// A log that answers the first read with `outcomes`' first, the second with its second,
        /// and every read after them with its last.
        init(reads outcomes: [ConsoleEarlierProcess]) {
            precondition(!outcomes.isEmpty, "A fake system log needs an outcome to answer with")
            self.outcomes = outcomes
        }

        /// The reads made, oldest first.
        var reads: [Read] {
            readsMade.withLock(\.self)
        }

        func lines(loggedBy processIdentifier: Int32, since date: Date) -> ConsoleEarlierProcess {
            let index = readsMade.withLock { reads in
                reads.append(Read(processIdentifier: processIdentifier, since: date))
                return reads.count - 1
            }
            return outcomes[min(index, outcomes.count - 1)]
        }
    }
#endif
