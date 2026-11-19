#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite("App Info's Copy Info text")
    struct AppInfoCopyInfoTests {
        @Test("Copy Info gives each section's title and facts, then the profile and the entitlements by key")
        func everySection() {
            let facts = AppInfoFacts(
                sections: [
                    AppInfoFacts.Section(title: "Build", facts: [.init(label: "Version", value: "1.2.3"), .init(label: "Commit", value: "4f9c2e1")])
                ],
                signing: AppSigning(profile: .embedded(AppInfoFixtures.profile), entitlements: AppInfoFixtures.profile.entitlements)
            )
            let expected = """
            Build
            Version: 1.2.3
            Commit: 4f9c2e1

            Provisioning
            Name: iOS Team Provisioning Profile: com.example.App
            Team: Example Corp
            Team ID: ABCDE12345
            Created: 2026-01-15 12:00 UTC
            Expires: 2027-01-15 12:00 UTC
            Devices: 3

            Entitlements
            Source: Provisioning profile
            com.apple.developer.associated-domains: applinks:example.com, webcredentials:example.com
            keychain-access-groups: ABCDE12345.*
            get-task-allow: Yes
            application-identifier: ABCDE12345.com.example.App
            """

            let actual = facts.report

            #expect(actual == expected)
        }

        @Test("With no profile and no entitlements, Copy Info says None for each")
        func none() {
            let facts = AppInfoFacts(sections: [], signing: AppSigning(profile: .none, entitlements: nil))
            let expected = """
            Provisioning
            Profile: None

            Entitlements
            Entitlements: None
            """

            let actual = facts.report

            #expect(actual == expected)
        }

        @Test("Entitlements read as an empty dictionary say None too")
        func emptyEntitlements() {
            let signing = AppSigning(profile: .unreadable, entitlements: Entitlements(source: .codeSignature, entries: []))
            let facts = AppInfoFacts(sections: [], signing: signing)

            let actual = facts.report

            #expect(actual.hasSuffix("Profile: Unreadable\n\nEntitlements\nEntitlements: None"))
        }

        @Test("An expired profile's expiry says so")
        @MainActor
        func expired() throws {
            let model = try AppInfoModel(
                bundle: FakeBundleInfoSource(),
                device: FakeDeviceInfoSource(),
                process: FakeProcessMetricsSource(),
                signing: FakeSigningInformation(profile: AppInfoFixtures.profileData()),
                clock: FakeWallClock(AppInfoFixtures.expires)
            )
            model.perform(AppInfoCommand(.refresh))

            let actual = AppInfoFacts(snapshot: model.snapshot)

            #expect(actual.isProfileExpired)
            #expect(actual.report.contains("Expires: 2027-01-15 12:00 UTC (expired)"))
        }

        @Test("A profile before its expiry isn't marked expired")
        @MainActor
        func current() throws {
            let model = try AppInfoModel(
                bundle: FakeBundleInfoSource(),
                device: FakeDeviceInfoSource(),
                process: FakeProcessMetricsSource(),
                signing: FakeSigningInformation(profile: AppInfoFixtures.profileData()),
                clock: FakeWallClock(AppInfoFixtures.created)
            )
            model.perform(AppInfoCommand(.refresh))

            let actual = AppInfoFacts(snapshot: model.snapshot)

            #expect(!actual.isProfileExpired)
            #expect(actual.report.contains("Expires: 2027-01-15 12:00 UTC\n"))
        }
    }
#endif
