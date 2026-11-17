// The part of swift-log's API (apple/swift-log 1.16) that the README's swift-log bridge and its
// test use, declared with swift-log's names and signatures, so the README's bridge compiles here
// verbatim without swift-log in any target. The plugin depends on no logging package and neither do
// its tests; the app that bridges imports swift-log itself. The bodies do only what the test needs:
// the standard-error handler writes nothing, and bootstrapping again replaces the factory rather
// than trapping.
#if DEBUG
    import os

    struct Logger {
        enum Level: Sendable {
            case trace, debug, info, notice, warning, error, critical
        }

        typealias Metadata = [String: MetadataValue]

        enum MetadataValue: Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
            case string(String)

            var description: String {
                switch self {
                case let .string(value): value
                }
            }

            init(stringLiteral value: String) {
                self = .string(value)
            }
        }

        struct Message: Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
            let description: String

            init(stringLiteral value: String) {
                description = value
            }
        }

        let label: String
        var handler: any LogHandler

        init(label: String) {
            self.label = label
            handler = LoggingSystem.factory(label)
        }

        subscript(metadataKey key: String) -> Metadata.Value? {
            get { handler[metadataKey: key] }
            set { handler[metadataKey: key] = newValue }
        }

        /// Logs at the warning level; the source is the module of the file that logs, as
        /// swift-log takes it from `#fileID`.
        func warning(_ message: Message, metadata: Metadata? = nil, file: String = #fileID) {
            let module = String(file.prefix { $0 != "/" })
            handler.log(event: LogEvent(level: .warning, message: message, metadata: metadata, source: module))
        }
    }

    struct LogEvent: Sendable {
        var level: Logger.Level
        var message: Logger.Message
        var metadata: Logger.Metadata?
        var source: String
    }

    protocol LogHandler: Sendable {
        func log(event: LogEvent)
        subscript(metadataKey _: String) -> Logger.Metadata.Value? { get set }
        var metadata: Logger.Metadata { get set }
        var logLevel: Logger.Level { get set }
    }

    struct MultiplexLogHandler: LogHandler {
        private var handlers: [any LogHandler]

        init(_ handlers: [any LogHandler]) {
            self.handlers = handlers
        }

        var logLevel: Logger.Level {
            get { handlers.first?.logLevel ?? .info }
            set { handlers = handlers.map { var handler = $0; handler.logLevel = newValue; return handler } }
        }

        var metadata: Logger.Metadata {
            get { handlers.first?.metadata ?? [:] }
            set { handlers = handlers.map { var handler = $0; handler.metadata = newValue; return handler } }
        }

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { handlers.first?[metadataKey: key] }
            set { handlers = handlers.map { var handler = $0; handler[metadataKey: key] = newValue; return handler } }
        }

        func log(event: LogEvent) {
            for handler in handlers {
                handler.log(event: event)
            }
        }
    }

    struct StreamLogHandler: LogHandler {
        var logLevel = Logger.Level.info
        var metadata: Logger.Metadata = [:]

        static func standardError(label _: String) -> StreamLogHandler {
            StreamLogHandler()
        }

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(event _: LogEvent) {}
    }

    enum LoggingSystem {
        // OSAllocatedUnfairLock rather than Mutex, which needs iOS 18; the package supports iOS 17.
        private static let installed = OSAllocatedUnfairLock<@Sendable (String) -> any LogHandler>(initialState: { _ in StreamLogHandler() })

        static func bootstrap(_ factory: @escaping @Sendable (String) -> any LogHandler) {
            installed.withLock { $0 = factory }
        }

        /// The handler a new logger with `label` gets.
        fileprivate static func factory(_ label: String) -> any LogHandler {
            installed.withLock { $0 }(label)
        }
    }
#endif
