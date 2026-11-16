// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerPermissionsPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PermissionsViewTests {
        @Test("Each row shows its name, its status and the usage description that declares it")
        func row() throws {
            let camera = DeclaredPermission(
                kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans receipts")]
            )
            let sut = PermissionsView(
                rows: [PermissionRowState(permission: camera, status: .denied, request: .unavailable)],
                onRequest: { _ in }, onOpenSettings: { _ in }
            )

            let title = try sut.inspect().find(text: "Camera").string()
            let status = try sut.inspect().find(ViewType.Label.self).title().text().string()
            let description = try sut.inspect().find(text: "Scans receipts").string()
            let key = try sut.inspect().find(text: "NSCameraUsageDescription").string()

            #expect(title == "Camera")
            #expect(status == "Denied")
            #expect(description == "Scans receipts")
            #expect(key == "NSCameraUsageDescription")
        }

        @Test("Request shows only on the undecided row, and tapping it asks for that permission")
        func requestOnlyWhenUndecided() throws {
            let camera = DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            let contacts = DeclaredPermission(
                kind: .contacts, usageDescriptions: [UsageDescription(key: "NSContactsUsageDescription", text: "Friends")]
            )
            var requested: [PermissionKind] = []
            let sut = PermissionsView(
                rows: [
                    PermissionRowState(permission: camera, status: .authorized, request: .unavailable),
                    PermissionRowState(permission: contacts, status: .notDetermined, request: .available)
                ],
                onRequest: { requested.append($0) }, onOpenSettings: { _ in }
            )

            let buttons = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }
            try sut.inspect().find(button: "Request").tap()

            #expect(buttons == ["Open Settings", "Request", "Open Settings"])
            #expect(requested == [.contacts])
        }

        @Test("Open Settings shows on every row, and tapping it opens that permission's settings")
        func openSettings() throws {
            let camera = DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            let notifications = DeclaredPermission(kind: .notifications, usageDescriptions: [])
            var opened: [PermissionKind] = []
            let sut = PermissionsView(
                rows: [
                    PermissionRowState(permission: camera, status: .denied, request: .unavailable),
                    PermissionRowState(permission: notifications, status: .denied, request: .unavailable)
                ],
                onRequest: { _ in }, onOpenSettings: { opened.append($0) }
            )

            let buttons = try sut.inspect().findAll(ViewType.Button.self, where: { try $0.labelView().text().string() == "Open Settings" })
            try buttons.last?.tap()

            #expect(buttons.count == 2)
            #expect(opened == [.notifications])
        }

        @Test("A request on its way shows Asking in place of the button")
        func inProgress() throws {
            let camera = DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            let sut = PermissionsView(
                rows: [PermissionRowState(permission: camera, status: .notDetermined, request: .inProgress)],
                onRequest: { _ in }, onOpenSettings: { _ in }
            )

            let actual = try sut.inspect().find(text: "Asking…").string()

            #expect(actual == "Asking…")
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Request") }
        }

        @Test("An undecided permission whose request needs an undeclared key names the key and offers no Request")
        func needsKey() throws {
            let calendars = DeclaredPermission(
                kind: .calendars, usageDescriptions: [UsageDescription(key: "NSCalendarsUsageDescription", text: "Plans")]
            )
            let sut = PermissionsView(
                rows: [PermissionRowState(
                    permission: calendars, status: .notDetermined, request: .needsKey("NSCalendarsFullAccessUsageDescription")
                )],
                onRequest: { _ in }, onOpenSettings: { _ in }
            )
            let expected = "Asking needs NSCalendarsFullAccessUsageDescription in the Info.plist."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Request") }
        }

        @Test("Notifications say they need no usage description; local network says it has no status to read")
        func noDescriptionAndNoStatus() throws {
            let notifications = DeclaredPermission(kind: .notifications, usageDescriptions: [])
            let localNetwork = DeclaredPermission(
                kind: .localNetwork, usageDescriptions: [UsageDescription(key: "NSLocalNetworkUsageDescription", text: "Finds printers")]
            )
            let sut = PermissionsView(
                rows: [
                    PermissionRowState(permission: notifications, status: .provisional, request: .unavailable),
                    PermissionRowState(permission: localNetwork, status: .noStatusAPI, request: .unavailable)
                ],
                onRequest: { _ in }, onOpenSettings: { _ in }
            )
            let expected = "Declared. The system reports no status for it, so the plugin can't read one."

            let none = try sut.inspect().find(text: "Needs no usage description.").string()
            let statusless = try sut.inspect().find(text: expected).string()

            #expect(none == "Needs no usage description.")
            #expect(statusless == expected)
        }

        @Test("Request and Open Settings name the permission for VoiceOver")
        func accessibilityLabels() throws {
            let camera = DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            let sut = PermissionsView(
                rows: [PermissionRowState(permission: camera, status: .notDetermined, request: .available)],
                onRequest: { _ in }, onOpenSettings: { _ in }
            )

            let request = try sut.inspect().find(button: "Request").accessibilityLabel().string()
            let settings = try sut.inspect().find(button: "Open Settings").accessibilityLabel().string()

            #expect(request == "Request Camera access")
            #expect(settings == "Open Settings for Camera")
        }
    }
#endif
