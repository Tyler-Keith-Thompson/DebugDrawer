#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation

    /// A synthetic provisioning profile and the facts the views and snapshots show. No real
    /// profile is used: the device identifiers are made up.
    enum AppInfoFixtures {
        /// 2026-01-15 12:00 UTC.
        static let created = Date(timeIntervalSince1970: 1_768_478_400)
        /// 2027-01-15 12:00 UTC, a year after `created`.
        static let expires = Date(timeIntervalSince1970: 1_800_014_400)

        /// The property list a development profile holds, with three devices.
        static func profileDictionary() -> [String: Any] {
            [
                "AppIDName": "Example App",
                "Name": "iOS Team Provisioning Profile: com.example.App",
                "TeamName": "Example Corp",
                "TeamIdentifier": ["ABCDE12345"],
                "CreationDate": created,
                "ExpirationDate": expires,
                "ProvisionedDevices": ["00000000-0000000000000001", "00000000-0000000000000002", "00000000-0000000000000003"],
                "Entitlements": [
                    "application-identifier": "ABCDE12345.com.example.App",
                    "com.apple.developer.associated-domains": ["applinks:example.com", "webcredentials:example.com"],
                    "get-task-allow": true,
                    "keychain-access-groups": ["ABCDE12345.*"]
                ] as [String: Any],
                "UUID": "11111111-2222-3333-4444-555555555555",
                "Version": 1
            ]
        }

        /// A profile file's bytes: the XML property list between stand-ins for the CMS envelope's
        /// header and signature, binary bytes as a real envelope has on both sides.
        static func profileData(_ dictionary: [String: Any] = profileDictionary()) throws -> Data {
            let plist = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
            return Data([0x30, 0x82, 0x1F, 0x3A, 0x06, 0x09, 0x2A, 0x86, 0x48]) + plist + Data([0xA0, 0x82, 0x0D, 0x00, 0x30, 0x82])
        }

        /// The profile `profileData()` holds.
        static let profile = ProvisioningProfile(
            name: "iOS Team Provisioning Profile: com.example.App",
            teamName: "Example Corp",
            teamIdentifier: "ABCDE12345",
            creationDate: created,
            expirationDate: expires,
            devices: .listed(3),
            entitlements: Entitlements(source: .provisioningProfile, entries: [
                Entitlement(key: "com.apple.developer.associated-domains", value: .list(["applinks:example.com", "webcredentials:example.com"])),
                Entitlement(key: "keychain-access-groups", value: .list(["ABCDE12345.*"])),
                Entitlement(key: "get-task-allow", value: .boolean(true)),
                Entitlement(key: "application-identifier", value: .list(["ABCDE12345.com.example.App"]))
            ])
        )

        /// The Build, Runtime and Environment sections, with a commit, branch and CI build.
        static let sections: [AppInfoFacts.Section] = [
            AppInfoFacts.Section(title: "Build", facts: [
                .init(label: "Bundle ID", value: "com.example.App"),
                .init(label: "Version", value: "1.2.3"),
                .init(label: "Build", value: "45"),
                .init(label: "Commit", value: "4f9c2e1"),
                .init(label: "Branch", value: "release/2.4"),
                .init(label: "CI Build", value: "812")
            ]),
            AppInfoFacts.Section(title: "Runtime", facts: [
                .init(label: "Footprint", value: "182.4 MB"),
                .init(label: "Uptime", value: "2m 14s")
            ]),
            AppInfoFacts.Section(title: "Environment", facts: [
                .init(label: "iOS", value: "Version 18.4 (Build 22E240)"),
                .init(label: "Debugger", value: "Attached")
            ])
        ]
    }
#endif
