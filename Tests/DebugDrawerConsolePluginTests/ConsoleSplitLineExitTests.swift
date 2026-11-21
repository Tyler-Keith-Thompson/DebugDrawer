// Exit tests start a child process, which only the Mac's test runs can do. Capture redirects the
// process's stdout and stderr, so it is installed only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSplitLineExitTests {
        @Test("A line written to stdout in pieces, one cut inside an emoji, reaches the console as one whole line")
        func lineWrittenInPiecesArrivesWhole() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                // Each piece is its own write to the pipe, so the console may read it alone; the
                // marker follows them in the same pipe, so once it is listed they have arrived.
                @MainActor
                func writePiecesThenWaitForMarker() async {
                    let line = "Uploaded 🚀 to the café"
                    let bytes = Data("\(line)\n".utf8)
                    let emoji = bytes.firstIndex(of: 0xF0) ?? bytes.startIndex
                    let marker = "Written after the pieces"
                    let sut = ConsoleLogStore.shared
                    sut.install()

                    FileHandle.standardOutput.write(bytes[..<(emoji + 2)])
                    FileHandle.standardOutput.write(bytes[(emoji + 2)...])
                    FileHandle.standardOutput.write(Data("\(marker)\n".utf8))
                    var subscription: AnyCancellable?
                    let captured = await withCheckedContinuation { continuation in
                        subscription = sut.$lines
                            .first { lines in lines.contains { $0.text == marker } }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let expected = [line, marker]
                    let actual = captured.filter { $0.source == .stdout }.map(\.text)
                    #expect(actual == expected)
                }
                await writePiecesThenWaitForMarker()
            }
        }
    }
#endif
