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
                DefaultsEntry(id: "launchCount", key: "launchCount", value: "3", type: "Number", rawValue: 3),
                DefaultsEntry(id: "password", key: "password", value: "hunter2", type: "String", rawValue: "hunter2")
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

        @Test("The system's keys are not the app's")
        @MainActor func systemKeys() {
            #expect(UserDefaultsStore.isSystemKey("NSLanguages"))
            #expect(UserDefaultsStore.isSystemKey("com.apple.something"))
            #expect(!UserDefaultsStore.isSystemKey("launchCount"))
        }
    }
#endif
