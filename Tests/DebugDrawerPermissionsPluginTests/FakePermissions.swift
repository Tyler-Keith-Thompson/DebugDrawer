#if DEBUG
    @testable import DebugDrawerPermissionsPlugin

    /// Answers each status from a dictionary the test sets, records each request, and on a
    /// request sets the status the test says the user would choose.
    @MainActor
    final class FakePermissionAuthority: PermissionAuthority {
        var statuses: [PermissionKind: PermissionStatus]
        /// The status each request leaves behind, as the user's answer would.
        var answers: [PermissionKind: PermissionStatus] = [:]
        private(set) var requested: [PermissionKind] = []
        private(set) var reads = 0
        /// How many times the model let go of what reading took.
        private(set) var stops = 0

        init(statuses: [PermissionKind: PermissionStatus]) {
            self.statuses = statuses
        }

        func status(of permission: DeclaredPermission) async -> PermissionStatus {
            reads += 1
            return statuses[permission.kind] ?? .notDetermined
        }

        func request(_ permission: DeclaredPermission) async {
            requested.append(permission.kind)
            if let answer = answers[permission.kind] {
                statuses[permission.kind] = answer
            }
        }

        func stop() {
            stops += 1
        }
    }

    /// Holds the model's callback so the test can report a change, as the app becoming active
    /// would.
    @MainActor
    final class FakePermissionChangeSource: PermissionChangeSource {
        private var onChange: (@MainActor () async -> Void)?

        func observe(_ onChange: @escaping @MainActor () async -> Void) {
            self.onChange = onChange
        }

        /// How many times the model stopped observing.
        private(set) var stops = 0

        /// Whether the model is observing: it called `observe` and hasn't stopped since.
        var isObserving: Bool {
            onChange != nil
        }

        func stop() {
            stops += 1
            onChange = nil
        }

        /// Reports a change and returns once the model has handled it.
        func change() async {
            await onChange?()
        }
    }
#endif
