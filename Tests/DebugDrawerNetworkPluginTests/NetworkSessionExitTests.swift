// Exit tests start a child process, which only the Mac's test runs can do.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct NetworkSessionExitTests {
        @Test("Requests written before the app crashes are listed as the previous session by the next launch")
        func survivesCrash() async throws {
            // The children get a home folder of their own, so what they keep there (Application Support,
            // Caches, preferences) stays out of the Mac's, whatever runs the test; each checks it took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }

            await #expect(processExitsWith: .signal(SIGABRT)) { [home = home as String, path = directory.path(percentEncoded: false) as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                let storage = _NetworkSessionStorage(directory: URL(filePath: path, directoryHint: .isDirectory))
                let recorder = NetworkSessionRecorder(
                    try NetworkSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000)
                )
                for index in 1 ... 3 {
                    recorder.record(
                        NetworkEntry(
                            timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), method: "GET",
                            url: "https://api.example.com/\(index)", host: "api.example.com", path: "/\(index)", requestHeaders: [:],
                            requestBody: nil, statusCode: 200, isComplete: true
                        ),
                        original: nil,
                        redaction: .standard
                    )
                }
                // Written once the queue reaches this; then the app dies without unwinding.
                _ = await recorder.previousSessions()
                abort()
            }
            let sut = NetworkSessionRecorder(
                try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: directory)),
                started: Date(timeIntervalSince1970: 1_800_000_100)
            )
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session)

            #expect(actual.entries.map(\.url) == ["https://api.example.com/3", "https://api.example.com/2", "https://api.example.com/1"])
        }
    }
#endif
