#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite("Provisioning profiles")
    struct ProvisioningProfileTests {
        @Test("A profile's bytes give its name, team, dates, device count and entitlements")
        func parsesTheFixture() throws {
            let data = try AppInfoFixtures.profileData()
            let expected = AppInfoFixtures.profile

            let actual = try ProvisioningProfile(profileData: data)

            #expect(actual == expected)
        }

        @Test("A profile read from a file names its fields as the plugin shows them")
        func fieldsAsShown() throws {
            let data = try AppInfoFixtures.profileData()
            let expectedCreated = "2026-01-15 12:00 UTC"
            let expectedExpires = "2027-01-15 12:00 UTC"
            let expectedDevices = "3"

            let actual = try ProvisioningProfile(profileData: data)

            #expect(actual.name == "iOS Team Provisioning Profile: com.example.App")
            #expect(actual.teamName == "Example Corp")
            #expect(actual.teamIdentifier == "ABCDE12345")
            #expect(ProvisioningProfile.format(actual.creationDate) == expectedCreated)
            #expect(ProvisioningProfile.format(actual.expirationDate) == expectedExpires)
            #expect(actual.devices.text == expectedDevices)
        }

        @Test("A profile with no devices listed and ProvisionsAllDevices set is for every device")
        func allDevices() throws {
            var dictionary = AppInfoFixtures.profileDictionary()
            dictionary["ProvisionedDevices"] = nil
            dictionary["ProvisionsAllDevices"] = true
            let data = try AppInfoFixtures.profileData(dictionary)

            let actual = try ProvisioningProfile(profileData: data).devices

            #expect(actual == .all)
            #expect(actual.text == "All")
        }

        @Test("A profile naming no devices, as a distribution profile, lists none")
        func unlistedDevices() throws {
            var dictionary = AppInfoFixtures.profileDictionary()
            dictionary["ProvisionedDevices"] = nil
            let data = try AppInfoFixtures.profileData(dictionary)

            let actual = try ProvisioningProfile(profileData: data).devices

            #expect(actual == .unlisted)
            #expect(actual.text == "Not listed")
        }

        @Test("A profile with an empty device list has zero devices")
        func zeroDevices() throws {
            var dictionary = AppInfoFixtures.profileDictionary()
            dictionary["ProvisionedDevices"] = [String]()
            let data = try AppInfoFixtures.profileData(dictionary)

            let actual = try ProvisioningProfile(profileData: data).devices

            #expect(actual == .listed(0))
        }

        @Test("A bare property list, with no envelope around it, is read too")
        func bareList() throws {
            let data = try PropertyListSerialization.data(fromPropertyList: AppInfoFixtures.profileDictionary(), format: .xml, options: 0)

            let actual = try ProvisioningProfile(profileData: data)

            #expect(actual == AppInfoFixtures.profile)
        }

        @Test("Bytes with no property list in them aren't a profile", arguments: [Data(), Data("not a profile".utf8), Data("<?xml no end".utf8)])
        func noPropertyList(data: Data) {
            #expect(throws: ProvisioningProfile.MalformedProfile()) {
                try ProvisioningProfile(profileData: data)
            }
        }

        @Test(
            "A property list missing any of a profile's fields isn't a profile",
            arguments: ["Name", "TeamName", "TeamIdentifier", "CreationDate", "ExpirationDate", "Entitlements"]
        )
        func missingField(key: String) throws {
            var dictionary = AppInfoFixtures.profileDictionary()
            dictionary[key] = nil
            let data = try AppInfoFixtures.profileData(dictionary)

            #expect(throws: ProvisioningProfile.MalformedProfile()) {
                try ProvisioningProfile(profileData: data)
            }
        }

        @Test("A profile has expired at its expiration date, and not a second before")
        func expiry() {
            let profile = AppInfoFixtures.profile
            let justBefore = AppInfoFixtures.expires.addingTimeInterval(-1)

            #expect(profile.isExpired(at: AppInfoFixtures.expires))
            #expect(!profile.isExpired(at: justBefore))
        }
    }
#endif
