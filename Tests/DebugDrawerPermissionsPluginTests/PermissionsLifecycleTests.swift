#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerPermissionsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Permissions install and uninstall", .timeLimit(.minutes(1)))
    struct PermissionsLifecycleTests {
        private let camera = DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])

        private func makeDrawer(_ suite: String) throws -> DebugDrawer {
            try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))
        }

        @Test("Unregistering the plugin removes it, stops observing, lets go of the authority's managers and drops the statuses")
        func uninstallStopsObserving() async throws {
            let suite = "PermissionsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakePermissionChangeSource()
            let authority = FakePermissionAuthority(statuses: [.camera: .denied])
            let model = PermissionsModel(permissions: [camera], authority: authority, changes: changes)
            let sut = PermissionsPlugin(model: model)
            drawer.registerGlobal(sut)
            await model.refresh()

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(changes.stops == 1)
            #expect(!changes.isObserving)
            #expect(authority.stops == 1)
            #expect(!model.isObserving)
            #expect(model.statuses.isEmpty)
            #expect(model.rows.map(\.status) == [.checking])
        }

        @Test("Registering the plugin again observes the source again, and a change reads the statuses")
        func reinstallObservesAgain() async throws {
            let suite = "PermissionsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakePermissionChangeSource()
            let authority = FakePermissionAuthority(statuses: [.camera: .denied])
            let model = PermissionsModel(permissions: [camera], authority: authority, changes: changes)
            let sut = PermissionsPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)
            authority.statuses[.camera] = .authorized

            drawer.registerGlobal(sut)
            await changes.change()

            #expect(changes.isObserving)
            #expect(model.rows.map(\.status) == [.authorized])
        }

        @Test("Uninstalling twice stops the source and the authority once")
        func uninstallTwice() throws {
            let suite = "PermissionsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try makeDrawer(suite)
            let changes = FakePermissionChangeSource()
            let authority = FakePermissionAuthority(statuses: [:])
            let sut = PermissionsPlugin(model: PermissionsModel(permissions: [camera], authority: authority, changes: changes))
            drawer.registerGlobal(sut)

            sut.uninstall(from: drawer)
            sut.uninstall(from: drawer)

            #expect(changes.stops == 1)
            #expect(authority.stops == 1)
        }

        @Test("In two drawers the plugin observes until the last one uninstalls it")
        func twoDrawers() throws {
            let suite = "PermissionsLifecycleTests.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let first = try makeDrawer(suite)
            let second = try makeDrawer(suite)
            let changes = FakePermissionChangeSource()
            let sut = PermissionsPlugin(model: PermissionsModel(
                permissions: [camera], authority: FakePermissionAuthority(statuses: [:]), changes: changes
            ))
            first.registerGlobal(sut)
            second.registerGlobal(sut)

            first.unregisterGlobal(id: sut.id)
            let isObservingWithOneLeft = changes.isObserving
            second.unregisterGlobal(id: sut.id)

            #expect(isObservingWithOneLeft)
            #expect(!changes.isObserving)
        }
    }
#endif
