#if DEBUG
    @testable import DebugDrawerPermissionsPlugin
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PermissionsModelTests {
        @Test("Until read, every permission is checking; a read gives each its status")
        func firstRead() async {
            let permissions = [
                DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")]),
                DeclaredPermission(kind: .notifications, usageDescriptions: [])
            ]
            let authority = FakePermissionAuthority(statuses: [.camera: .denied, .notifications: .authorized])
            let sut = PermissionsModel(permissions: permissions, authority: authority, changes: FakePermissionChangeSource())
            let before = sut.rows.map(\.status)

            await sut.refresh()

            #expect(before == [.checking, .checking])
            #expect(sut.rows.map(\.status) == [.denied, .authorized])
        }

        @Test("A reported change, as the app becoming active after Settings, reads every status again")
        func changeRereads() async {
            let permissions = [
                DeclaredPermission(kind: .contacts, usageDescriptions: [UsageDescription(key: "NSContactsUsageDescription", text: "Friends")])
            ]
            let authority = FakePermissionAuthority(statuses: [.contacts: .authorized])
            let changes = FakePermissionChangeSource()
            let sut = PermissionsModel(permissions: permissions, authority: authority, changes: changes)
            await sut.refresh()
            authority.statuses[.contacts] = .denied

            await changes.change()

            #expect(sut.rows.map(\.status) == [.denied])
        }

        @Test("The model keeps its change source alive, so changes keep being reported for as long as the plugin is installed")
        func keepsChangeSource() {
            let permissions = [DeclaredPermission(kind: .notifications, usageDescriptions: [])]
            weak var source: FakePermissionChangeSource?

            let sut = PermissionsModel(permissions: permissions, authority: FakePermissionAuthority(statuses: [:]), changes: {
                let changes = FakePermissionChangeSource()
                source = changes
                return changes
            }())

            #expect(source != nil)
            withExtendedLifetime(sut) {}
        }

        @Test("Request asks the authority, then reads the answer, after which there is nothing to ask")
        func request() async {
            let permissions = [
                DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            ]
            let authority = FakePermissionAuthority(statuses: [.camera: .notDetermined])
            authority.answers[.camera] = .authorized
            let sut = PermissionsModel(permissions: permissions, authority: authority, changes: FakePermissionChangeSource())
            await sut.refresh()
            let before = sut.rows.map(\.request)

            await sut.request(.camera)

            #expect(before == [.available])
            #expect(authority.requested == [.camera])
            #expect(sut.rows.map(\.status) == [.authorized])
            #expect(sut.rows.map(\.request) == [.unavailable])
        }

        @Test("A permission already decided is never requested")
        func requestDecided() async {
            let permissions = [
                DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            ]
            let authority = FakePermissionAuthority(statuses: [.camera: .denied])
            let sut = PermissionsModel(permissions: permissions, authority: authority, changes: FakePermissionChangeSource())
            await sut.refresh()

            await sut.request(.camera)

            #expect(authority.requested.isEmpty)
        }

        @Test("A permission whose request needs an undeclared key is never requested")
        func requestNeedsKey() async {
            let permissions = [
                DeclaredPermission(kind: .calendars, usageDescriptions: [UsageDescription(key: "NSCalendarsUsageDescription", text: "Plans")])
            ]
            let authority = FakePermissionAuthority(statuses: [.calendars: .notDetermined])
            let sut = PermissionsModel(permissions: permissions, authority: authority, changes: FakePermissionChangeSource())
            await sut.refresh()

            await sut.request(.calendars)

            #expect(authority.requested.isEmpty)
            #expect(sut.rows.map(\.request) == [.needsKey("NSCalendarsFullAccessUsageDescription")])
        }

        @Test("A read that finishes after a later one began is dropped, so older statuses never replace newer ones")
        func staleReadDropped() async {
            /// Holds the first read until the test lets it go; answers later reads at once.
            @MainActor
            final class GatedAuthority: PermissionAuthority {
                var status: PermissionStatus = .authorized
                private var gate: CheckedContinuation<Void, Never>?
                private var arrived: CheckedContinuation<Void, Never>?
                private var reads = 0

                func status(of _: DeclaredPermission) async -> PermissionStatus {
                    reads += 1
                    let answer = status
                    if reads == 1 {
                        await withCheckedContinuation { continuation in
                            gate = continuation
                            arrived?.resume()
                            arrived = nil
                        }
                    }
                    return answer
                }

                func request(_: DeclaredPermission) async {}

                /// Returns once the first read is held at the gate.
                func firstReadArrived() async {
                    guard gate == nil else { return }
                    await withCheckedContinuation { arrived = $0 }
                }

                func open() {
                    gate?.resume()
                    gate = nil
                }
            }
            let permissions = [
                DeclaredPermission(kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans")])
            ]
            let authority = GatedAuthority()
            let sut = PermissionsModel(permissions: permissions, authority: authority, changes: FakePermissionChangeSource())
            let first = Task { await sut.refresh() }
            await authority.firstReadArrived()
            authority.status = .denied

            await sut.refresh()
            authority.open()
            await first.value

            #expect(sut.rows.map(\.status) == [.denied])
        }
    }
#endif
