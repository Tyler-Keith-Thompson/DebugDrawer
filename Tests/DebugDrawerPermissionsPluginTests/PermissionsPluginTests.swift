#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerPermissionsPlugin
    import Foundation
    import Testing
    #if os(iOS)
        import UIKit
    #endif

    @MainActor
    @Suite
    struct PermissionsPluginTests {
        @Test("The plugin is Permissions, in the App category, and adds to bug reports")
        func identity() {
            let model = PermissionsModel(permissions: [], authority: FakePermissionAuthority(statuses: [:]), changes: FakePermissionChangeSource())

            let sut = PermissionsPlugin(model: model)

            #expect(sut.id == "PermissionsPlugin")
            #expect(sut.title == "Permissions")
            #expect(sut.category == "App")
            #expect(sut.icon == "lock.shield")
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The bug report gets permissions.txt: each permission with its status and the keys that declare it")
        func report() throws {
            let location = DeclaredPermission(kind: .location, usageDescriptions: [
                UsageDescription(key: "NSLocationWhenInUseUsageDescription", text: "Nearby stores"),
                UsageDescription(key: "NSLocationAlwaysAndWhenInUseUsageDescription", text: "Tracks runs")
            ])
            let notifications = DeclaredPermission(kind: .notifications, usageDescriptions: [])
            let rows = [
                PermissionRowState(permission: location, status: .authorizedWhenInUse, request: .unavailable),
                PermissionRowState(permission: notifications, status: .notDetermined, request: .available)
            ]
            let expected = """
            Location: While Using
              NSLocationWhenInUseUsageDescription: Nearby stores
              NSLocationAlwaysAndWhenInUseUsageDescription: Tracks runs
            Notifications: Not Asked
              (needs no usage description)
            """
            var actual = DebugDrawerReport()

            PermissionsPlugin.contribute(rows, to: &actual)

            let file = try #require(actual.files.first)
            #expect(actual.files.map(\.name) == ["permissions.txt"])
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        #if os(macOS)
            @Test("On macOS, Open Settings opens the permission's pane under Privacy & Security, or the notifications pane")
            func macOSSettings() {
                let kinds: [PermissionKind] = [.camera, .location, .notifications, .unrecognized(key: "NSFaceIDUsageDescription")]
                let expected = [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
                    "x-apple.systempreferences:com.apple.preference.notifications",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy"
                ]

                let actual = kinds.map { $0.settingsURL?.absoluteString }

                #expect(actual == expected)
            }

            @Test("On macOS, Motion and the media library are not on this platform")
            func macOSAvailability() {
                let kinds: [PermissionKind] = [.motion, .mediaLibrary, .camera, .tracking]

                let actual = kinds.map(\.existsOnThisPlatform)

                #expect(actual == [false, false, true, true])
            }
        #elseif os(iOS)
            @Test("On iOS, Open Settings opens the app's page in Settings, or its notification settings")
            func iOSSettings() {
                let kinds: [PermissionKind] = [.camera, .location, .notifications]
                let expected = [
                    UIApplication.openSettingsURLString, UIApplication.openSettingsURLString, UIApplication.openNotificationSettingsURLString
                ]

                let actual = kinds.map { $0.settingsURL?.absoluteString }

                #expect(actual == expected)
            }
        #endif
    }
#endif
