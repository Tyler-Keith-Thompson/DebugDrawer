// Exit tests start a child process, which only the Mac's test runs can do. Capture redirects the
// process's stdout and stderr, so it is installed only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsolePrintLineExitTests {
        @Test("A line printed after the console captures stdout reaches the console as one line, with no flush")
        func printedLineArrivesAlone() async {
            await #expect(processExitsWith: .success) {
                // The marker goes straight to the descriptor, behind the printed line in the same
                // pipe, so once the marker is listed the printed line has arrived too, or it is
                // still held in stdout's buffer.
                @MainActor
                func printThenWaitForMarker() async {
                    let printed = "Printed without a flush"
                    let marker = "Written past stdout's buffer"
                    let sut = ConsoleLogStore.shared
                    sut.install()

                    print(printed)
                    FileHandle.standardOutput.write(Data("\(marker)\n".utf8))
                    var subscription: AnyCancellable?
                    let captured = await withCheckedContinuation { continuation in
                        subscription = sut.$lines
                            .first { lines in lines.contains { $0.text == marker } }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let expected = [printed, marker]
                    let actual = captured.filter { $0.source == .stdout }.map(\.text)
                    #expect(actual == expected)
                }
                await printThenWaitForMarker()
            }
        }
    }
#endif
