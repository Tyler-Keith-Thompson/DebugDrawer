// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    import DebugDrawerReceiver
    import Testing

    @Suite
    struct DiagnosticsCaptureExitTests {
        @Test("A value pattern that isn't a regular expression traps, rather than letting what it was meant to mask through")
        func invalidPatternTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerDiagnosticsRedaction(values: ["(unclosed"])
            }
        }

        @Test("Adding a value pattern that isn't a regular expression traps")
        func invalidAddedPatternTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerDiagnosticsRedaction.standard.adding(values: ["[z-a]"])
            }
        }

        @Test("Limits that keep no line, request or byte, or a negative body size, trap")
        func emptyLimitsTrap() async {
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerDiagnosticsCapture.Limits(lines: 0, requests: 1, bodyBytes: 0, totalBytes: 1)
            }
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerDiagnosticsCapture.Limits(lines: 1, requests: 0, bodyBytes: 0, totalBytes: 1)
            }
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerDiagnosticsCapture.Limits(lines: 1, requests: 1, bodyBytes: -1, totalBytes: 1)
            }
            await #expect(processExitsWith: .failure) {
                _ = DebugDrawerDiagnosticsCapture.Limits(lines: 1, requests: 1, bodyBytes: 0, totalBytes: 0)
            }
        }
    }
#endif
