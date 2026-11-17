#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // The sink feeds the shared store, which other suites clear, so each test logs a message of its
    // own and waits for the store's lines to hold it. The store publishes its lines in batches; the
    // buffer keeps every batch the test hasn't read yet, so none is missed while it looks at one.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleLogSinkTests {
        @Test("Calling the sink adds a line with the level, message, metadata, subsystem and category it was given")
        func sinkAddsALine() async throws {
            let message = "Payment declined \(UUID())"
            let expectedMetadata = ["order": "1042", "user": "7"]

            ConsoleLogSink.log(
                level: .error, message: message, metadata: expectedMetadata, subsystem: "com.example.shop", category: "checkout"
            )
            var found: LogLine?
            let arrivals = ConsoleLogStore.shared.$lines
                .compactMap { lines in lines.last { $0.text == message } }
                .buffer(size: 64, prefetch: .keepFull, whenFull: .dropOldest)
            for await line in arrivals.values {
                found = line
                break
            }
            let actual = try #require(found)

            #expect(actual.level == .error)
            #expect(actual.source == .sink)
            #expect(actual.metadata == expectedMetadata)
            #expect(actual.subsystem == "com.example.shop")
            #expect(actual.category == "checkout")
        }

        @Test("Lines logged through the sink from another thread arrive in the order they were logged")
        func backgroundOrder() async throws {
            let prefix = "Background \(UUID())"
            let expected = (0 ..< 5).map { "\(prefix) \($0)" }

            await Task.detached {
                for message in expected {
                    ConsoleLogSink.log(level: .info, message: message)
                }
            }.value
            var found: [String]?
            let arrivals = ConsoleLogStore.shared.$lines
                .map { lines in lines.map(\.text).filter { $0.hasPrefix(prefix) } }
                .filter { $0.count == expected.count }
                .buffer(size: 64, prefetch: .keepFull, whenFull: .dropOldest)
            for await texts in arrivals.values {
                found = texts
                break
            }
            let actual = try #require(found)

            #expect(actual == expected)
        }

        @Test("A line without metadata, subsystem or category has none")
        func defaults() async throws {
            let message = "Plain \(UUID())"

            ConsoleLogSink.log(level: .debug, message: message)
            var found: LogLine?
            let arrivals = ConsoleLogStore.shared.$lines
                .compactMap { lines in lines.last { $0.text == message } }
                .buffer(size: 64, prefetch: .keepFull, whenFull: .dropOldest)
            for await line in arrivals.values {
                found = line
                break
            }
            let actual = try #require(found)

            #expect(actual.level == .debug)
            #expect(actual.metadata.isEmpty)
            #expect(actual.subsystem.isEmpty)
            #expect(actual.category.isEmpty)
            #expect(actual.shownMetadata == nil)
        }

        @Test("Each sink level becomes the Console's level of the same name")
        func levels() {
            let expected: [LogLine.Level] = [.debug, .info, .notice, .error, .fault]

            let actual = ConsoleLogSink.Level.allCases.map(LogLine.Level.init)

            #expect(actual == expected)
        }
    }
#endif
