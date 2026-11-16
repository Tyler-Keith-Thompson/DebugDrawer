#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite
    struct AppInfoReportTests {
        @Test("The report gets app-info.json: an object of every fact's label and value")
        func factsAsJSON() throws {
            let facts = AppInfoFacts(sections: [
                [.init(label: "Bundle ID", value: "com.example.shop"), .init(label: "Version", value: "2.1 (40)")],
                [.init(label: "PID", value: "123")]
            ])
            let expected = """
            {
              "Bundle ID" : "com.example.shop",
              "PID" : "123",
              "Version" : "2.1 (40)"
            }
            """
            var actual = DebugDrawerReport()

            AppInfoPlugin.contribute(facts, to: &actual, redaction: .standard)

            let file = try #require(actual.files.first)
            #expect(file.name == "app-info.json")
            #expect(file.kind == .json)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("A fact whose label matches a key pattern is masked")
        func sensitiveFactMasked() throws {
            let facts = AppInfoFacts(sections: [[.init(label: "Session", value: "abc")]])
            var report = DebugDrawerReport()

            AppInfoPlugin.contribute(facts, to: &report, redaction: .standard)

            let file = try #require(report.files.first)
            let actual = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: String])
            #expect(actual == ["Session": DebugDrawerRedaction.mask])
        }
    }
#endif
