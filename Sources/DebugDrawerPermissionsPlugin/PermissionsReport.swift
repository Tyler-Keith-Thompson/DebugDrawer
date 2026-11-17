#if DEBUG
    import DebugDrawer

    extension PermissionsPlugin: DebugDrawerReportContributor {
        /// Adds `permissions.txt`: each declared permission with its status when last read.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(model.rows, to: &report)
        }

        /// Adds `rows` as `permissions.txt`, a line per permission (`Camera: Denied`) and an
        /// indented line per usage description. Nothing is redacted: the descriptions are the
        /// app's own text, shown to every user.
        static func contribute(_ rows: [PermissionRowState], to report: inout DebugDrawerReport) {
            report.add(text: text(of: rows), named: "permissions.txt")
        }

        static func text(of rows: [PermissionRowState]) -> String {
            rows.map { row in
                let declarations = row.permission.usageDescriptions.isEmpty
                    ? ["  (needs no usage description)"]
                    : row.permission.usageDescriptions.map { "  \($0.key): \($0.text)" }
                return (["\(row.permission.kind.title): \(row.status.title)"] + declarations).joined(separator: "\n")
            }
            .joined(separator: "\n")
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension PermissionsPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
