// ViewInspector is linked on Apple platforms only, and views are tested on the Mac.
#if os(macOS) && DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite("App Info's signing views")
    struct AppInfoSigningViewTests {
        @Test("Provisioning lists the profile's name, team, dates and device count")
        func provisioning() throws {
            let sut = AppInfoProvisioningSection(profile: .embedded(AppInfoFixtures.profile), isExpired: false)
            let expected = [
                "Provisioning",
                "Name", "iOS Team Provisioning Profile: com.example.App",
                "Team", "Example Corp",
                "Team ID", "ABCDE12345",
                "Created", "2026-01-15 12:00 UTC",
                "Expires", "2027-01-15 12:00 UTC",
                "Devices", "3"
            ]

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(actual == expected)
        }

        @Test("An expired profile shows an Expired warning")
        func expired() throws {
            let sut = AppInfoProvisioningSection(profile: .embedded(AppInfoFixtures.profile), isExpired: true)

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(actual.contains("Profile — Expired"))
        }

        @Test("A profile that hasn't expired shows no warning")
        func notExpired() throws {
            let sut = AppInfoProvisioningSection(profile: .embedded(AppInfoFixtures.profile), isExpired: false)

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(!actual.contains("Profile — Expired"))
        }

        @Test("With no profile, Provisioning shows a None row")
        func noProfile() throws {
            let sut = AppInfoProvisioningSection(profile: .none, isExpired: false)
            let expected = ["Provisioning", "Profile", "None"]

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(actual == expected)
        }

        @Test("An unreadable profile says so")
        func unreadableProfile() throws {
            let sut = AppInfoProvisioningSection(profile: .unreadable, isExpired: false)

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(actual.contains("Profile — Unreadable"))
        }

        @Test("Entitlements name the common keys in words, list each associated domain, and show switches as Yes or No")
        func entitlements() throws {
            let sut = AppInfoEntitlementsSection(entitlements: AppInfoFixtures.profile.entitlements)
            let expected = [
                "Entitlements",
                "Associated domains", "applinks:example.com", "webcredentials:example.com",
                "Keychain access groups", "ABCDE12345.*",
                "Get task allow", "Yes",
                "App ID", "ABCDE12345.com.example.App",
                "Allowed by the provisioning profile; the app's signature may hold fewer."
            ]

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(actual == expected)
        }

        @Test("A key with no word label is shown as the key")
        func rawKey() throws {
            let entitlements = Entitlements(source: .codeSignature, entries: [Entitlement(key: "com.example.custom", value: .boolean(false))])
            let sut = AppInfoEntitlementsSection(entitlements: entitlements)
            let expected = ["Entitlements", "com.example.custom", "No", "From the app's code signature."]

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(actual == expected)
        }

        @Test(
            "With no entitlements, or an empty set, Entitlements shows a None row",
            arguments: [nil, Entitlements(source: .codeSignature, entries: [])]
        )
        func noEntitlements(entitlements: Entitlements?) throws {
            let sut = AppInfoEntitlementsSection(entitlements: entitlements)
            // The heading and the row's label are both "Entitlements", which read as one once
            // repeated texts are dropped.
            let expected = ["Entitlements", "None"]

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            #expect(actual == expected)
        }

        @Test("The facts view shows the build metadata, then Provisioning and Entitlements")
        func factsView() throws {
            let facts = AppInfoFacts(sections: AppInfoFixtures.sections, signing: AppSigning(profile: .none, entitlements: nil))
            let sut = AppInfoFactsView(facts: facts) {}

            // A one-token value is found once per layout it may take; each is the same text.
            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { texts, text in if texts.last != text { texts.append(text) } }

            let commit = try #require(actual.firstIndex(of: "4f9c2e1"))
            let provisioning = try #require(actual.firstIndex(of: "Provisioning"))
            let entitlements = try #require(actual.lastIndex(of: "Entitlements"))
            #expect(actual.contains("release/2.4"))
            #expect(actual.contains("812"))
            #expect(commit < provisioning)
            #expect(provisioning < entitlements)
        }
    }
#endif
