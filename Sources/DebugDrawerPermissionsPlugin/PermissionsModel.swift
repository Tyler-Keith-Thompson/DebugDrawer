#if DEBUG
    import Combine
    import os

    /// The declared permissions and their statuses, read again on every change the source
    /// reports and after every request.
    @MainActor
    final class PermissionsModel: ObservableObject {
        let permissions: [DeclaredPermission]
        @Published private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
        /// The permissions asked for whose request hasn't returned.
        @Published private(set) var requesting: Set<PermissionKind> = []

        private static let logger = Logger(subsystem: "DebugDrawerPermissionsPlugin", category: "PermissionsModel")
        private let authority: any PermissionAuthority
        /// Kept for the model's life: the source holds its observers weakly, so the model is what
        /// keeps it reporting.
        private let changes: any PermissionChangeSource
        /// Counts reads, so a read that finishes after a later one began is dropped rather than
        /// overwriting newer statuses.
        private var latestRead = 0

        /// - Parameters:
        ///   - permissions: What the Info.plist declares, in the drawer's order.
        ///   - authority: Reads and requests them.
        ///   - changes: Says when to read them again; observed from now on.
        init(permissions: [DeclaredPermission], authority: any PermissionAuthority, changes: any PermissionChangeSource) {
            self.permissions = permissions
            self.authority = authority
            self.changes = changes
            changes.observe { [weak self] in await self?.refresh() }
        }

        /// Each permission with its status (`checking` until first read) and what asking would do.
        var rows: [PermissionRowState] {
            permissions.map { permission in
                let status = statuses[permission.kind] ?? .checking
                return PermissionRowState(
                    permission: permission,
                    status: status,
                    request: PermissionRequest(permission: permission, status: status, isRequesting: requesting.contains(permission.kind))
                )
            }
        }

        /// Reads every status again.
        func refresh() async {
            latestRead += 1
            let read = latestRead
            var statuses: [PermissionKind: PermissionStatus] = [:]
            for permission in permissions {
                statuses[permission.kind] = await authority.status(of: permission)
            }
            guard read == latestRead else {
                Self.logger.debug("Dropped a read that a later one overtook")
                return
            }
            Self.logger.debug("Read \(statuses.count) statuses: \(statuses.values.map(\.title).sorted(), privacy: .public)")
            self.statuses = statuses
        }

        /// Asks for `kind` if the drawer may (its request is `available`), then reads every status
        /// again.
        func request(_ kind: PermissionKind) async {
            guard let row = rows.first(where: { $0.permission.kind == kind }), row.request == .available else { return }
            requesting.insert(kind)
            await authority.request(row.permission)
            requesting.remove(kind)
            await refresh()
        }
    }
#endif
