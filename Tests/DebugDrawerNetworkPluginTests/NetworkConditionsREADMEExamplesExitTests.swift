// The README's Network conditions example, verbatim, so the README cannot drift from the code. It
// runs in a child process, as installing registers the URL protocol and swizzles every session
// configuration in the process that runs it. It is in a file of its own, as exit tests need one,
// and lives here rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("README examples, in a child process: Network conditions")
    struct NetworkConditionsREADMEExamplesExitTests {
        @Test("Network conditions: the installed offline profile fails a request to its host through URLSession.shared")
        func networkConditions() async {
            await #expect(processExitsWith: .success) {
                // The profiles are saved in the test runner's folder of Application Support: the
                // home folder can't be moved once the process has read it (HOME set here is
                // ignored), so the child removes what it saved before it exits.
                let saved = _NetworkMockStorage.defaultDirectory
                await MainActor.run {
                    let slowImages = NetworkConditionProfile(
                        id: UUID(uuidString: "8C4F2A61-7B3D-4E59-A1C8-2D6E9F0B3A47")!,
                        name: "Slow images",
                        host: .wildcard("*.cdn.example.com"),
                        latency: .seconds(2),
                        bandwidth: 50_000
                    )
                    let paymentsOffline = NetworkConditionProfile(
                        id: UUID(uuidString: "5E9B1D73-2C48-4F6A-B0E5-7A3C8D1F2E96")!,
                        name: "Payments offline",
                        host: .exact("payments.example.com"),
                        failureRate: 100,
                        failure: .notConnectedToInternet
                    )
                    DebugDrawer.shared.installNetwork(conditions: [slowImages, paymentsOffline])
                }
                guard let url = URL(string: "https://payments.example.com/v1/charge") else { exit(EXIT_FAILURE) }
                var code: URLError.Code?
                do {
                    _ = try await URLSession.shared.data(from: url)
                } catch let error as URLError {
                    code = error.code
                } catch {
                    code = nil
                }
                let profiles = await MainActor.run { NetworkConditionsModel.shared.profiles.map(\.name) }
                let isExpected = code == .notConnectedToInternet && profiles == ["Slow images", "Payments offline"]
                try? FileManager.default.removeItem(at: saved)
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
