import DebugDrawer
import DebugDrawerConsolePlugin
import Foundation

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The Console plugin's install.
enum ExampleConsole {
    /// Launched with this argument and a number, `-ConsoleSessionsKept 2`, the app keeps that many
    /// earlier launches' log lines rather than five, so pruning can be checked by relaunching.
    static let sessionsArgument = "-ConsoleSessionsKept"

    /// Installs the Console plugin, keeping the number of sessions the launch argument asks for.
    @MainActor
    static func install() {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let kept = arguments.firstIndex(of: sessionsArgument)
                .flatMap { arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil }
                .map { max($0, 0) }
            let sessions = kept.map { ConsoleSessionPersistence(maxSessions: $0) } ?? .standard
            DebugDrawer.shared.installConsole(sessions: sessions)
        #endif
    }
}
