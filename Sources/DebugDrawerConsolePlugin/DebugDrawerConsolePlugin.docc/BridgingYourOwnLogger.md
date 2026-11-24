# Bridging Your Own Logger

Send lines from swift-log, CocoaLumberjack or the app's own logger to the Console.

## Overview

The Console captures the process's os_log entries and, on macOS, its stdout and stderr. On iOS it
captures neither stream, because redirecting them would cut Xcode's debugger off from them. A
logger that writes through swift-log, CocoaLumberjack or the app's own code doesn't reach os_log,
so the Console can't capture its lines from there. Send them to `ConsoleLogSink` instead, from any
thread:

```swift
import DebugDrawerConsolePlugin

ConsoleLogSink.log(
    level: .error, message: "Payment declined", metadata: ["order": "1042"],
    subsystem: "com.example.shop", category: "checkout"
)
```

### How a sink line shows

The line shows its metadata after its text as quiet `key=value` fields (`order=1042`), or under the
text at accessibility text sizes. The search matches metadata keys and values as it does the text.
The subsystem and category show and mute like an os_log line's. Copy All, the bug report and the
sessions on disk keep the metadata; a field the redaction rules call sensitive is masked in a copy
or report.

`ConsoleLogSink` exists in release builds too. There `log` does nothing and evaluates none of its
arguments, so the bridge needs no `#if DEBUG`.

### A swift-log handler

The plugin depends on no logging package, so the app writes the bridge. For swift-log, that is a
`LogHandler` that passes each entry on, with the logger's label as the subsystem and the module
that logged it as the category:

```swift
import DebugDrawerConsolePlugin
import Logging

/// Sends each swift-log entry to the Console: the label as the subsystem, the module that logged
/// it as the category, and the handler's and the entry's metadata as key/value fields.
struct ConsoleLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level = .trace
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let merged = metadata.merging(event.metadata ?? [:]) { _, logged in logged }
        ConsoleLogSink.log(
            level: ConsoleLogSink.Level(event.level),
            message: event.message.description,
            metadata: merged.mapValues(\.description),
            subsystem: label,
            category: event.source
        )
    }
}

extension ConsoleLogSink.Level {
    init(_ level: Logger.Level) {
        switch level {
        case .trace, .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning, .error: self = .error
        case .critical: self = .fault
        }
    }
}

LoggingSystem.bootstrap { label in
    MultiplexLogHandler([StreamLogHandler.standardError(label: label), ConsoleLogHandler(label: label)])
}
```

Lines sent through the sink are written to the session on disk as they arrive, so they survive a
crash; see <doc:ConsoleSessions>.
