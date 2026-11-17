#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkConditionProfileFileTests {
        @Test("Profiles survive a save and a load: every field, every host kind and every failure")
        func roundTrip() throws {
            let expected = [
                NetworkConditionProfile(name: "Everything", latency: .milliseconds(250)),
                NetworkConditionProfile(name: "API", isEnabled: false, host: .exact("api.example.com"), bandwidth: 97500, failureRate: 10),
                NetworkConditionProfile(name: "CDN", host: .wildcard("*.cdn.example.com"), failure: .notConnectedToInternet),
                NetworkConditionProfile(name: "Regex", host: .regex(#"api\d"#), latency: .seconds(2), failureRate: 100, failure: .internalServerError)
            ]

            let actual = try NetworkConditionProfileFile.decode(NetworkConditionProfileFile.encode(expected))

            #expect(actual == expected)
        }

        @Test("The file names its version and writes the latency in milliseconds")
        func format() throws {
            let profile = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(), name: "Slow", latency: .milliseconds(1500)
            )

            let text = String(bytes: NetworkConditionProfileFile.encode([profile]), encoding: .utf8) ?? ""

            #expect(text.contains(#""version" : 1"#))
            #expect(text.contains(#""latencyMilliseconds" : 1500"#))
            #expect(!text.contains("bandwidth"))
        }

        @Test("A profile missing the optional fields loads with their defaults: on, every host, no effect")
        func defaults() throws {
            let data = Data(#"{"version":1,"profiles":[{"id":"00000000-0000-0000-0000-000000000002","name":"Bare"}]}"#.utf8)
            let expected = [NetworkConditionProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(), name: "Bare")]

            let actual = try NetworkConditionProfileFile.decode(data)

            #expect(actual == expected)
        }

        @Test("A file of a later version, or of version 0, is refused; one that isn't the format is unreadable")
        func refusesUnknownFiles() {
            #expect(throws: NetworkMockRuleFile.ReadError.unsupportedVersion(2)) {
                try NetworkConditionProfileFile.decode(Data(#"{"version":2,"profiles":[]}"#.utf8))
            }
            #expect(throws: NetworkMockRuleFile.ReadError.unsupportedVersion(0)) {
                try NetworkConditionProfileFile.decode(Data(#"{"version":0,"profiles":[]}"#.utf8))
            }
            #expect(throws: NetworkMockRuleFile.ReadError.unreadable) {
                try NetworkConditionProfileFile.decode(Data(#"{"version":1,"profiles":[{"name":"No id"}]}"#.utf8))
            }
            #expect(throws: NetworkMockRuleFile.ReadError.unreadable) {
                try NetworkConditionProfileFile.decode(Data("[]".utf8))
            }
        }

        @Test("The default storage keeps the profiles in conditions.json in its directory, beside the mock rules")
        func storageFile() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "NetworkConditionStorage-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = _NetworkConditionStorage(directory: directory)
            let expected = Data("{}".utf8)

            let before = try sut.readProfiles()
            try sut.writeProfiles(expected)
            let actual = try sut.readProfiles()

            #expect(before == nil)
            #expect(actual == expected)
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: "conditions.json").path(percentEncoded: false)))
        }
    }
#endif
