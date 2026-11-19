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
        func networkMocks() async {
            await #expect(processExitsWith: .success) {
                // The rules are saved in Application Support, under the home folder the test
                // runners point at a temporary one (CFFIXED_USER_HOME).
                await MainActor.run {
                    let outage = NetworkMockRule(
                        id: UUID(uuidString: "3F2B8E1C-0D4A-4B7E-9C61-5A2D7E8F9B10")!,
                        name: "Orders outage",
                        matcher: .init(methods: ["GET", "POST"], host: .wildcard("*.example.com"), path: .wildcard("/v1/orders/**")),
                        response: .init(status: 503, body: .text(#"{"error":"maintenance"}"#), contentType: "application/json")
                    )
                    DebugDrawer.shared.installNetwork(mocks: [outage])
                }
                guard let url = URL(string: "https://api.example.com/v1/orders/42/items") else { exit(EXIT_FAILURE) }
                let answer = try? await URLSession.shared.data(from: url)
                let status = (answer?.1 as? HTTPURLResponse)?.statusCode
                let isExpected = status == 503 && answer?.0 == Data(#"{"error":"maintenance"}"#.utf8)
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Network, apps that pin certificates: the bypassed host and its subdomains never reach the URL protocol; other hosts do")
        func networkBypassing() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    DebugDrawer.shared.installNetwork(bypassing: ["api.example.com"])
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
