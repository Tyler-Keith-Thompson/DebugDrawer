#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite
    struct AppInfoReportTests {
        @Test("The report gets app-info.json: each section's facts by label, the profile, and the entitlements by key")
        func factsAsJSON() throws {
            let facts = AppInfoFacts(
                sections: [
                    AppInfoFacts.Section(title: "Build", facts: [
                        .init(label: "Bundle ID", value: "com.example.shop"),
                        .init(label: "Version", value: "2.1"),
                        .init(label: "Commit", value: "4f9c2e1"),
                        .init(label: "Branch", value: "release/2.4"),
                        .init(label: "CI Build", value: "812")
                    ]),
                    AppInfoFacts.Section(title: "Runtime", facts: [.init(label: "PID", value: "123")])
                ],
                signing: AppSigning(profile: .embedded(AppInfoFixtures.profile), entitlements: AppInfoFixtures.profile.entitlements)
            )
            let expected = """
            {
              "Build" : {
                "Branch" : "release/2.4",
                "Bundle ID" : "com.example.shop",
                "CI Build" : "812",
                "Commit" : "4f9c2e1",
                "Version" : "2.1"
              },
              "Entitlements" : {
                "Source" : "Provisioning profile",
                "application-identifier" : "ABCDE12345.com.example.App",
                "com.apple.developer.associated-domains" : "applinks:example.com, webcredentials:example.com",
                "get-task-allow" : "Yes",
                "keychain-access-groups" : "ABCDE12345.*"
              },
              "Provisioning" : {
                "Created" : "2026-01-15 12:00 UTC",
                "Devices" : "3",
                "Expires" : "2027-01-15 12:00 UTC",
                "Name" : "iOS Team Provisioning Profile: com.example.App",
                "Team" : "Example Corp",
                "Team ID" : "ABCDE12345"
              },
              "Runtime" : {
                "PID" : "123"
              }
            }
            """
            var actual = DebugDrawerReport()

            AppInfoPlugin.contribute(facts, to: &actual, redaction: .standard)

            let file = try #require(actual.files.first)
            #expect(file.name == "app-info.json")
            #expect(file.kind == .json)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("With no profile and no entitlements, the report says None for each")
        func none() throws {
            let facts = AppInfoFacts(sections: [], signing: AppSigning(profile: .none, entitlements: nil))
            let expected: [String: [String: String]] = [
                "Provisioning": ["Profile": "None"],
                "Entitlements": ["Entitlements": "None"]
            ]
            var report = DebugDrawerReport()

            AppInfoPlugin.contribute(facts, to: &report, redaction: .standard)

            let file = try #require(report.files.first)
            let actual = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: [String: String]])
            #expect(actual == expected)
        }

        @Test("A fact whose label matches a key pattern is masked")
        func sensitiveFactMasked() throws {
            let facts = AppInfoFacts(sections: [AppInfoFacts.Section(title: "Runtime", facts: [.init(label: "Session", value: "abc")])])
            var report = DebugDrawerReport()

            AppInfoPlugin.contribute(facts, to: &report, redaction: .standard)

            let file = try #require(report.files.first)
            let actual = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: [String: String]])
            #expect(actual["Runtime"] == ["Session": DebugDrawerRedaction.mask])
        }

        @Test("The plugin's own contribution carries the build metadata it was installed with")
        @MainActor
        func pluginContribution() throws {
            let signing = AppSigningStore(source: FakeSigningInformation())
            let metadata = AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "main", ciBuildNumber: "812")
            let sut = AppInfoPlugin(buildMetadata: metadata, signing: signing)
            let expected = ["Commit": "4f9c2e1", "Branch": "main", "CI Build": "812"]
            var report = DebugDrawerReport()

            sut.contribute(to: &report, redaction: .standard)

            let file = try #require(report.files.first)
            let actual = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: [String: String]])
            let build = try #require(actual["Build"])
            #expect(build.filter { expected.keys.contains($0.key) } == expected)
            #expect(actual["Provisioning"] == ["Profile": "None"])
            #expect(actual["Entitlements"] == ["Entitlements": "None"])
        }
    }
#endif
