#if DEBUG
    import Foundation

    public extension DebugDrawer {
        /// The installed plugins that add files to the bug report: global plugins, then local
        /// ones, each ID once.
        var reportContributors: [AnyDebugDrawerPlugin] {
            var seen = Set<String>()
            return (globalPlugins + localPlugins).filter { $0.contributesToReport && seen.insert($0.id).inserted }
        }

        /// Writes a bug report of every installed plugin that adopts
        /// ``DebugDrawerReportContributor``, with `redaction` applied, and zips it.
        ///
        /// The zip holds one folder, `<App>-Report-<ISO 8601 date with - for :>`, with a
        /// `summary.txt` (the app, its version, the OS, the device model, the date and the list of
        /// files) and a folder of files per contributing plugin, named after its title.
        ///
        /// - Parameter directory: Where the zip goes; created if missing. Defaults to the
        ///   temporary directory.
        /// - Returns: The zip's URL.
        /// - Throws: ``DebugDrawerReport/WriteFailed`` when a file can't be written or zipped.
        func createReport(in directory: URL = FileManager.default.temporaryDirectory) throws(DebugDrawerReport.WriteFailed) -> URL {
            // A plugin's contribution may read its files: the drawer's own work, like the writing.
            let report = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                DebugDrawerReport(contributionsOf: reportContributors, redaction: redaction)
            }
            return try report.writeArchive(summary: .current(at: Date()), in: directory)
        }
    }
#else
    import Foundation

    // The release stand-ins: release builds have no plugins to report on.
    public extension DebugDrawer {
        /// Always empty.
        var reportContributors: [AnyDebugDrawerPlugin] {
            []
        }

        /// Throws: release builds make no reports.
        ///
        /// - Parameter directory: Ignored.
        /// - Returns: Never returns.
        /// - Throws: ``DebugDrawerReport/WriteFailed``, always.
        func createReport(in directory: URL = FileManager.default.temporaryDirectory) throws(DebugDrawerReport.WriteFailed) -> URL {
            throw DebugDrawerReport.WriteFailed()
        }
    }
#endif
