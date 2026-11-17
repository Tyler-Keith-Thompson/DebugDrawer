// The README's "Console: your own logger" examples, verbatim, so the README cannot drift from the
// code. The swift-log bridge compiles against Fakes/SwiftLogAPI.swift, which declares the part of
// swift-log's API it uses, in place of the README's `import Logging`: no target depends on
// swift-log. It lives here rather than in DebugDrawerTests, which links core alone.
#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

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

    // The store publishes its lines in batches; the buffer keeps every batch the test hasn't read
    // yet, so none is missed while it looks at one.
    @MainActor
    @Suite("README examples: Console: your own logger", .timeLimit(.minutes(1)))
    struct ConsoleLogSinkREADMEExamplesTests {
        @Test("Console: your own logger: a line logged to the sink, with its metadata, subsystem and category")
        func sink() async throws {
            ConsoleLogSink.log(
                level: .error, message: "Payment declined", metadata: ["order": "1042"],
                subsystem: "com.example.shop", category: "checkout"
            )

            var found: LogLine?
            let arrivals = ConsoleLogStore.shared.$lines
                .compactMap { lines in lines.last { $0.text == "Payment declined" && $0.category == "checkout" } }
                .buffer(size: 64, prefetch: .keepFull, whenFull: .dropOldest)
            for await line in arrivals.values {
                found = line
                break
            }
            let actual = try #require(found)
            #expect(actual.level == .error)
            #expect(actual.metadata == ["order": "1042"])
            #expect(actual.subsystem == "com.example.shop")
        }

        @Test("Console: your own logger: the swift-log bridge sends a logger's entries with the label, module and metadata")
        func swiftLogBridge() async throws {
            LoggingSystem.bootstrap { label in
                MultiplexLogHandler([StreamLogHandler.standardError(label: label), ConsoleLogHandler(label: label)])
            }

            var logger = Logger(label: "com.example.cart")
            logger[metadataKey: "session"] = "s-9"
            logger.warning("Coupon rejected", metadata: ["coupon": "SPRING"])
            var found: LogLine?
            let arrivals = ConsoleLogStore.shared.$lines
                .compactMap { lines in lines.last { $0.text == "Coupon rejected" } }
                .buffer(size: 64, prefetch: .keepFull, whenFull: .dropOldest)
            for await line in arrivals.values {
                found = line
                break
            }
            let actual = try #require(found)
            #expect(actual.level == .error)
            #expect(actual.metadata == ["coupon": "SPRING", "session": "s-9"])
            #expect(actual.subsystem == "com.example.cart")
            #expect(actual.category == "DebugDrawerConsolePluginTests")
        }

        @Test("Each swift-log level maps to the Console level the README's bridge names")
        func levels() {
            let levels: [Logger.Level] = [.trace, .debug, .info, .notice, .warning, .error, .critical]
            let expected: [ConsoleLogSink.Level] = [.debug, .debug, .info, .notice, .error, .error, .fault]

            let actual = levels.map(ConsoleLogSink.Level.init)

            #expect(actual == expected)
        }
    }
#endif
