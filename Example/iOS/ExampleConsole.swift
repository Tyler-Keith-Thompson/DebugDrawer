import DebugDrawer
import DebugDrawerConsolePlugin
import Foundation
import os

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The Console plugin's install, and the lines the Print button logs.
enum ExampleConsole {
    private static let installLogger = Logger(subsystem: "ExampleApp_iOS", category: "ExampleConsole")

    /// Launched with this argument and a number, `-ConsoleSessionsKept 2`, the app keeps that many
    /// earlier launches' log lines rather than five, so pruning can be checked by relaunching.
    static let sessionsArgument = "-ConsoleSessionsKept"

    private static let logger = Logger(subsystem: "ExampleApp_iOS", category: "ExampleConsole")

    /// Installs the Console plugin, keeping the number of sessions the launch argument asks for.
    @MainActor
    static func install() {
        do {
            try installThrowing()
        } catch {
            installLogger.error("The Console plugin refused its configuration: \(String(describing: error), privacy: .public)")
        }
    }

    /// What ``install()`` does, throwing what the plugin refuses.
    @MainActor
    private static func installThrowing() throws {
        let arguments = ProcessInfo.processInfo.arguments
        let kept = arguments.firstIndex(of: sessionsArgument)
            .flatMap { arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil }
            .map { max($0, 0) }
        let sessions = try kept.map { try ConsoleSessionPersistence(maxSessions: $0) } ?? .standard
        DebugDrawer.shared.installConsole(sessions: sessions)
    }

    /// Logs `message` to the unified log, which the Console reads on iOS; it doesn't capture
    /// stdout there, so a `print` alone wouldn't show.
    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    private static let feedLogger = Logger(subsystem: "com.example.feed", category: "networking")
    private static let cartLogger = Logger(subsystem: "com.example.cart", category: "ui")

    /// Logs a line to each of two subsystems, so the Console's subsystem and category filters
    /// and mutes have something to work on.
    static func logSubsystems(_ counter: Int) {
        feedLogger.info("GET /feed?page=\(counter, privacy: .public) 200")
        cartLogger.error("Cart badge shows \(counter, privacy: .public) items, expected 0")
    }
}
