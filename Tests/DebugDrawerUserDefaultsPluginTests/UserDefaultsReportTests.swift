#if DEBUG
    import DebugDrawer
    import Foundation
    import Testing
    @testable import DebugDrawerUserDefaultsPlugin

    @Suite
    struct UserDefaultsReportTests {
        @Test("The report gets user-defaults.json with each key's type and value, a password key masked")
        func defaultsAsJSON() throws {
            let entries = [
                DefaultsEntry(key: "launchCount", value: .number(3)),
                DefaultsEntry(key: "password", value: .string("hunter2"))
            ]
            let expected = """
            {
              "launchCount" : {
                "type" : "Number",
                "value" : "3"
              },
              "password" : {
                "type" : "String",
                "value" : "[REDACTED]"
              }
            }
            """
            var actual = DebugDrawerReport()

            UserDefaultsPlugin.contribute(entries, to: &actual, redaction: .standard)

            let file = try #require(actual.files.first)
            #expect(file.name == "user-defaults.json")
            #expect(file.kind == .json)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("No keys add nothing to the report")
        func noKeys() {
            var actual = DebugDrawerReport()

            UserDefaultsPlugin.contribute([], to: &actual, redaction: .standard)

            #expect(actual.files.isEmpty)
        }
    }
#endif
