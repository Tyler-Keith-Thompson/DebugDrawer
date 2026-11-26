// The README's Network mocks and bypassing examples, verbatim, so the README cannot drift from the code. It runs
// in a child process, as installing registers the URL protocol and swizzles every session
// configuration in the process that runs it. It is in a file of its own, as exit tests need one,
// and lives here rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("README examples, in a child process")
    struct NetworkREADMEExamplesExitTests {
        @Test("Network mocks: the installed rule answers a matching request through URLSession.shared")
        func networkMocks() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                // The rules are saved in Application Support, in the child's temporary home
                // folder (CFFIXED_USER_HOME above).
                try await MainActor.run {
                    let outage = NetworkMockRule(
                        id: UUID(uuidString: "3F2B8E1C-0D4A-4B7E-9C61-5A2D7E8F9B10")!,
                        name: "Orders outage",
                        matcher: .init(methods: ["GET", "POST"], host: .wildcard("*.example.com"), path: .wildcard("/v1/orders/**")),
                        response: .init(status: 503, body: .text(#"{"error":"maintenance"}"#), contentType: "application/json")
                    )
                    try DebugDrawer.shared.installNetwork(mocks: [outage])
                }
                guard let url = URL(string: "https://api.example.com/v1/orders/42/items") else { exit(EXIT_FAILURE) }
                let answer = try? await URLSession.shared.data(from: url)
                let status = (answer?.1 as? HTTPURLResponse)?.statusCode
                let isExpected = status == 503 && answer?.0 == Data(#"{"error":"maintenance"}"#.utf8)
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Network, apps that pin certificates: the bypassed host and its subdomains never reach the URL protocol; other hosts do")
        func networkBypassing() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                try await MainActor.run {
                    try DebugDrawer.shared.installNetwork(bypassing: ["api.example.com"])
                }
                guard let bypassed = URL(string: "https://api.example.com/v1/devices"),
                      let subdomain = URL(string: "https://eu.api.example.com/v1/devices"),
                      let other = URL(string: "https://cdn.example.com/logo.png")
                else { exit(EXIT_FAILURE) }
                let isExpected = !DebugNetworkProtocol.canInit(with: URLRequest(url: bypassed))
                    && !DebugNetworkProtocol.canInit(with: URLRequest(url: subdomain))
                    && DebugNetworkProtocol.canInit(with: URLRequest(url: other))
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
