#if DEBUG
    @testable import DebugDrawerPermissionsPlugin
    import Testing

    @Suite
    struct PermissionRequestTests {
        @Test("Asking is offered only while the user hasn't decided")
        func onlyUndecided() {
            let camera = DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            let statuses: [PermissionStatus] = [.notDetermined, .authorized, .denied, .restricted, .limited, .checking]
            let expected: [PermissionRequest] = [.available, .unavailable, .unavailable, .unavailable, .unavailable, .unavailable]

            let actual = statuses.map { PermissionRequest(permission: camera, status: $0, isRequesting: false) }

            #expect(actual == expected)
        }

        @Test("A request on its way is in progress, whatever the status read before it")
        func inProgress() {
            let camera = DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])

            let actual = PermissionRequest(permission: camera, status: .notDetermined, isRequesting: true)

            #expect(actual == .inProgress)
        }

        @Test("Calendars with the legacy key alone need the full-access key to ask")
        func legacyCalendars() {
            let legacy = DeclaredPermission(
                kind: .calendars, usageDescriptions: [UsageDescription(key: "NSCalendarsUsageDescription", text: "Plans")]
            )
            let writeOnly = DeclaredPermission(
                kind: .calendars, usageDescriptions: [UsageDescription(key: "NSCalendarsWriteOnlyAccessUsageDescription", text: "Adds")]
            )

            let actualLegacy = PermissionRequest(permission: legacy, status: .notDetermined, isRequesting: false)
            let actualWriteOnly = PermissionRequest(permission: writeOnly, status: .notDetermined, isRequesting: false)

            #expect(actualLegacy == .needsKey("NSCalendarsFullAccessUsageDescription"))
            #expect(actualWriteOnly == .available)
        }

        @Test("Reminders with the legacy key alone need the full-access key to ask")
        func legacyReminders() {
            let legacy = DeclaredPermission(kind: .reminders, usageDescriptions: [UsageDescription(key: "NSRemindersUsageDescription", text: "Nags")])

            let actual = PermissionRequest(permission: legacy, status: .notDetermined, isRequesting: false)

            #expect(actual == .needsKey("NSRemindersFullAccessUsageDescription"))
        }

        @Test("Location asks for when-in-use access, which needs its own key")
        func location() {
            let alwaysOnly = DeclaredPermission(
                kind: .location, usageDescriptions: [UsageDescription(key: "NSLocationAlwaysAndWhenInUseUsageDescription", text: "Tracks")]
            )
            let whenInUse = DeclaredPermission(
                kind: .location, usageDescriptions: [UsageDescription(key: "NSLocationWhenInUseUsageDescription", text: "Nearby")]
            )

            let actualAlwaysOnly = PermissionRequest(permission: alwaysOnly, status: .notDetermined, isRequesting: false)
            let actualWhenInUse = PermissionRequest(permission: whenInUse, status: .notDetermined, isRequesting: false)

            #expect(actualAlwaysOnly == .needsKey("NSLocationWhenInUseUsageDescription"))
            #expect(actualWhenInUse == .available)
        }

        @Test("Notifications can be asked for with nothing declared")
        func notifications() {
            let notifications = DeclaredPermission(kind: .notifications, usageDescriptions: [])

            let actual = PermissionRequest(permission: notifications, status: .notDetermined, isRequesting: false)

            #expect(actual == .available)
        }
    }
#endif
