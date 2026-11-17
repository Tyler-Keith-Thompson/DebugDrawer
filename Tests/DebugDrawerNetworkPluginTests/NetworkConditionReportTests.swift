#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkConditionReportTests {
        @Test("The HTTP Archive's comment names the profile that conditioned a request and what it did, after the mock that answered it")
        func archiveComment() {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let conditioned = NetworkEntry(
                timestamp: start, method: "GET", url: "https://api.example.com/a", host: "api.example.com", path: "/a",
                requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 2, isComplete: true, mockRuleName: "Greeting",
                conditionEffect: NetworkConditionEffect(profileName: "Slow API", latency: .milliseconds(2000), bandwidth: nil, failure: nil)
            )
            let plain = NetworkEntry(
                timestamp: start, method: "GET", url: "https://api.example.com/b", host: "api.example.com", path: "/b",
                requestHeaders: [:], requestBody: nil, statusCode: 200, duration: 0.1, isComplete: true
            )

            let entries = HTTPArchive([conditioned, plain], redaction: .none).log.entries
            let actualConditioned = entries.first { $0.request.url.hasSuffix("/a") }?.comment
            let actualPlain = entries.first { $0.request.url.hasSuffix("/b") }?.comment

            #expect(actualConditioned == "Answered by the network mock “Greeting”. Conditioned by “Slow API”: Delayed 2,000 ms")
            #expect(entries.count == 2)
            #expect(actualPlain == nil)
        }
    }
#endif
