import Foundation
import os

/// Lines for the Console plugin, one at each level it shows.
@MainActor
enum TestBenchConsole {
    private static let logger = Logger(subsystem: "com.debugdrawer.example.testbench", category: "TestBench")

    /// Logs a line at each unified-log level, debug to fault, then writes one to standard output and
    /// one to standard error, which the Console reads on macOS only.
    static func logEveryLevel() async -> String {
        logger.debug("Test bench: a debug line")
        logger.info("Test bench: an info line")
        logger.notice("Test bench: a notice line")
        logger.error("Test bench: an error line")
        logger.fault("Test bench: a fault line")
        print("Test bench: a line on standard output")
        FileHandle.standardError.write(Data("Test bench: a line on standard error\n".utf8))
        return "Logged debug, info, notice, error and fault, then stdout and stderr"
    }
}
