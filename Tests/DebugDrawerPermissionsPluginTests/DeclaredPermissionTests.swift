#if DEBUG
    @testable import DebugDrawerPermissionsPlugin
    import Testing

    @Suite
    struct DeclaredPermissionTests {
        @Test("Only the kinds with a usage description are listed, with notifications, which need none")
        func onlyDeclared() {
            let infoDictionary: [String: Any] = [
                "CFBundleIdentifier": "com.example.app",
                "NSCameraUsageDescription": "Scans receipts",
                "NSContactsUsageDescription": "Finds friends"
            ]
            let expected: [PermissionKind] = [.camera, .contacts, .notifications]

            let actual = DeclaredPermission.declared(in: infoDictionary).map(\.kind)

            #expect(actual == expected)
        }

        @Test("An empty Info.plist lists notifications alone")
        func empty() {
            let expected = [DeclaredPermission(kind: .notifications, usageDescriptions: [])]

            let actual = DeclaredPermission.declared(in: [:])

            #expect(actual == expected)
        }

        @Test("A kind declared by several keys is listed once, with each key's description in the kind's order")
        func severalKeys() throws {
            let infoDictionary: [String: Any] = [
                "NSLocationAlwaysAndWhenInUseUsageDescription": "Tracks runs",
                "NSLocationWhenInUseUsageDescription": "Shows nearby stores"
            ]
            let expected = [
                UsageDescription(key: "NSLocationWhenInUseUsageDescription", text: "Shows nearby stores"),
                UsageDescription(key: "NSLocationAlwaysAndWhenInUseUsageDescription", text: "Tracks runs")
            ]

            let declared = DeclaredPermission.declared(in: infoDictionary)
            let actual = try #require(declared.first)

            #expect(declared.map(\.kind) == [.location, .notifications])
            #expect(actual.usageDescriptions == expected)
        }

        @Test("Calendars are declared by the full-access, write-only or legacy key")
        func calendarKeys() {
            let keys = ["NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription", "NSCalendarsUsageDescription"]

            let actual = keys.map { DeclaredPermission.declared(in: [$0: "Plans trips"]).first?.kind }

            #expect(actual == [.calendars, .calendars, .calendars])
        }

        @Test("Each photo library key is its own permission, as the system asks for each separately")
        func photoKeys() {
            let infoDictionary: [String: Any] = [
                "NSPhotoLibraryAddUsageDescription": "Saves edits",
                "NSPhotoLibraryUsageDescription": "Picks a photo"
            ]
            let expected: [PermissionKind] = [.photoLibrary, .photoLibraryAdd, .notifications]

            let actual = DeclaredPermission.declared(in: infoDictionary).map(\.kind)

            #expect(actual == expected)
        }

        @Test("An empty or non-string usage description doesn't declare the permission")
        func emptyDescription() {
            let infoDictionary: [String: Any] = ["NSCameraUsageDescription": "", "NSMicrophoneUsageDescription": 1]
            let expected: [PermissionKind] = [.notifications]

            let actual = DeclaredPermission.declared(in: infoDictionary).map(\.kind)

            #expect(actual == expected)
        }

        @Test("Other usage descriptions are listed after the recognized kinds, sorted by key")
        func unrecognized() {
            let infoDictionary: [String: Any] = [
                "NSHealthShareUsageDescription": "Reads steps",
                "NSFaceIDUsageDescription": "Unlocks the vault",
                "NSCameraUsageDescription": "Scans receipts",
                "NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true]
            ]
            let expected: [PermissionKind] = [
                .camera, .notifications, .unrecognized(key: "NSFaceIDUsageDescription"), .unrecognized(key: "NSHealthShareUsageDescription")
            ]

            let actual = DeclaredPermission.declared(in: infoDictionary).map(\.kind)

            #expect(actual == expected)
        }

        @Test("Every recognized kind is found from each of its keys")
        func everyKey() {
            let kinds = PermissionKind.recognized.filter { $0 != .notifications }

            let actual = kinds.allSatisfy { kind in
                kind.keys.allSatisfy { PermissionKind(usageDescriptionKey: $0) == kind }
            }

            #expect(actual)
        }

        @Test("A key that isn't a usage description is no kind")
        func notAKey() {
            let actual = PermissionKind(usageDescriptionKey: "CFBundleIdentifier")

            #expect(actual == nil)
        }
    }
#endif
