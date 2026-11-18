#if DEBUG
    @testable import DebugDrawerCrashReportsPlugin
    import Foundation
    import Testing

    @Suite
    struct CrashFileTests {
        @Test("A signal's file reads as the signal's name and meaning, its time, version and frames")
        func signal() throws {
            let text = """
            DebugDrawer crash report 1
            app 1.2 (34)
            time 1763290000
            signal 11
            frames
            0   Example   0x0000000100004000 $s7Example5crashyyF + 12
            1   Example   0x0000000100004100 $s7Example4mainyyF + 40
            end

            """
            let id = UUID()
            let expected = CrashReport(
                id: id,
                date: Date(timeIntervalSince1970: 1_763_290_000),
                title: "SIGSEGV",
                reason: "Segmentation fault: an access to memory the app doesn't own",
                appVersion: "1.2 (34)",
                frames: [
                    "0   Example   0x0000000100004000 $s7Example5crashyyF + 12",
                    "1   Example   0x0000000100004100 $s7Example4mainyyF + 40"
                ],
                source: .captured,
                isSeen: false
            )

            let actual = try #require(CrashFile.parse(text, id: id, fallbackDate: .distantPast))

            #expect(actual == expected)
        }

        @Test("An exception's file reads as the exception, its reason and its own stack, not the abort's")
        func exception() throws {
            let text = """
            DebugDrawer crash report 1
            app 1.0
            time 1763290000
            exception NSInvalidArgumentException
            reason *** -[__NSArrayI objectAtIndex:]: index 5 beyond bounds
            reason on two lines
            exception-frames
            0   CoreFoundation   0x0000000180a0a2ec __exceptionPreprocess + 176
            1   libobjc.A.dylib   0x00000001804f2788 objc_exception_throw + 60
            end
            signal 6
            frames
            0   libsystem_kernel.dylib   0x0000000180d5e5f0 __pthread_kill + 8
            end

            """
            let expectedFrames = [
                "0   CoreFoundation   0x0000000180a0a2ec __exceptionPreprocess + 176",
                "1   libobjc.A.dylib   0x00000001804f2788 objc_exception_throw + 60"
            ]
            let expectedReason = "*** -[__NSArrayI objectAtIndex:]: index 5 beyond bounds\non two lines"

            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast))

            #expect(actual.title == "NSInvalidArgumentException")
            #expect(actual.reason == expectedReason)
            #expect(actual.appVersion == "1.0")
            #expect(actual.frames == expectedFrames)
        }

        @Test("A file cut off inside its frames keeps the frames written before the cut")
        func truncated() throws {
            let text = """
            DebugDrawer crash report 1
            time 1763290000
            signal 5
            frames
            0   Example   0x0000000100004000 $s7Example5crashyyF + 12
            1   Exam
            """
            let expectedFrames = ["0   Example   0x0000000100004000 $s7Example5crashyyF + 12", "1   Exam"]

            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast))

            #expect(actual.title == "SIGTRAP")
            #expect(actual.appVersion == nil)
            #expect(actual.frames == expectedFrames)
        }

        @Test("A file cut off before its time takes the fallback date, and one with no frames has none")
        func noTime() throws {
            let text = "DebugDrawer crash report 1\nsignal 6\n"
            let expected = Date(timeIntervalSince1970: 42)

            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: expected))

            #expect(actual.date == expected)
            #expect(actual.title == "SIGABRT")
            #expect(actual.frames.isEmpty)
        }

        @Test("A file that names neither a signal nor an exception is no report")
        func headerOnly() {
            let text = "DebugDrawer crash report 1\napp 1.0\ntime 1763290000\n"

            let actual = CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast)

            #expect(actual == nil)
        }

        @Test("Text that isn't a crash file is no report", arguments: ["", "garbage\nsignal 11\n", "\u{0}\u{1}\u{2}"])
        func garbage(text: String) {
            let actual = CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast)

            #expect(actual == nil)
        }

        @Test("A signal the handler doesn't catch is named by its number")
        func unknownSignal() throws {
            let text = "DebugDrawer crash report 1\nsignal 30\n"

            let actual = try #require(CrashFile.parse(text, id: UUID(), fallbackDate: .distantPast))

            #expect(actual.title == "Signal 30")
        }

        @Test("A report's text has its title, reason, date, version and source, then its frames")
        func text() {
            let sut = CrashReport(
                id: UUID(),
                date: Date(timeIntervalSince1970: 1_763_290_000),
                title: "SIGTRAP",
                reason: "Trap",
                appVersion: "1.2 (34)",
                frames: ["0 Example 0x1", "1 Example 0x2"],
                source: .captured,
                isSeen: false
            )
            let expected = """
            SIGTRAP: Trap
            Date: 2025-11-16T10:46:40Z
            App: 1.2 (34)
            Source: Captured

            0 Example 0x1
            1 Example 0x2

            """

            let actual = sut.text()

            #expect(actual == expected)
        }

        @Test("A report's text, which Copy Report copies, keeps each frame's line as backtrace_symbols_fd wrote it, padding and offset included")
        func textKeepsUnparsedFrames() {
            let frames = [
                "0   libsystem_kernel.dylib              0x00000001802a1a6c __pthread_kill + 8",
                "1   CoreFoundation                      0x00000001804b8c40 -[NSObject(NSObject) doesNotRecognizeSelector:] + 136",
                "2   Example                             0x0000000104a1c3d8 $s7Example11ContentViewV5crashyyF + 52"
            ]
            let sut = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 0), title: "SIGABRT", reason: nil, appVersion: nil,
                frames: frames, source: .captured, isSeen: true
            )
            let expected = "SIGABRT\nDate: 1970-01-01T00:00:00Z\nSource: Captured\n\n" + frames.joined(separator: "\n") + "\n"

            let actual = sut.text()

            #expect(actual == expected)
        }

        @Test("A report without frames, reason or version says no stack trace was recorded")
        func textWithoutFrames() {
            let sut = CrashReport(
                id: UUID(), date: Date(timeIntervalSince1970: 0), title: "SIGBUS", reason: nil, appVersion: nil,
                frames: [], source: .metricKit, isSeen: true
            )
            let expected = "SIGBUS\nDate: 1970-01-01T00:00:00Z\nSource: MetricKit\n\nNo stack trace was recorded.\n"

            let actual = sut.text()

            #expect(actual == expected)
        }
    }
#endif
