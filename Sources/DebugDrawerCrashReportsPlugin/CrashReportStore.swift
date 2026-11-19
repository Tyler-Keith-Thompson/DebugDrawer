#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation

    /// The crash reports kept in a directory: the crash file the handlers left, read on the next
    /// launch, and one JSON file per report, the newest ``limit`` kept.
    ///
    /// The directory is the seam tests replace (a temporary one): the signal handler can only
    /// write a file, so a protocol over storage would still need a real path beside it.
    /// Main-actor isolated, like the drawer that shows and edits it. Its file work is the
    /// drawer's own, which Disk I/O leaves out.
    @MainActor
    final class CrashReportStore: ObservableObject {
        /// How many reports are kept; adding one more deletes the oldest.
        static let limit = 10

        let directory: URL
        /// Every report kept, newest first; empty while unloaded.
        @Published private(set) var reports: [CrashReport] = []
        /// Whether ``reports`` holds what the directory does, rather than being dropped by
        /// ``unload()``.
        private(set) var isLoaded = true
        /// Called with the number of unseen reports whenever the reports change.
        private let onUnseenCountChange: @MainActor (Int) -> Void

        /// The reports kept in `directory`, which is created if missing.
        ///
        /// - Parameters:
        ///   - directory: Where the crash file and the reports live.
        ///   - onUnseenCountChange: Called with the number of unseen reports whenever the reports
        ///     change: the plugin's badge.
        init(directory: URL, onUnseenCountChange: @escaping @MainActor (Int) -> Void = { _ in }) {
            self.directory = directory
            self.onUnseenCountChange = onUnseenCountChange
            reports = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                return Self.load(from: directory)
            }
        }

        /// Reads the reports from the directory again, after ``unload()``; does nothing while they
        /// are loaded.
        func load() {
            guard !isLoaded else { return }
            isLoaded = true
            update(DebugDrawerActivity.$isDrawerWork.withValue(true) { Self.load(from: directory) })
        }

        /// Drops the reports from memory, leaving their files, until ``load()``.
        func unload() {
            guard isLoaded else { return }
            isLoaded = false
            update([])
        }

        /// The file the crash handlers write.
        var crashFile: URL {
            directory.appending(path: CrashFile.name)
        }

        /// How many reports the developer hasn't opened.
        var unseenCount: Int {
            reports.count { !$0.isSeen }
        }

        /// Reads the crash file the last run left, keeps its report and deletes the file; `nil`
        /// when there is none or it isn't a crash file.
        ///
        /// - Parameter id: The new report's identity.
        @discardableResult
        func collectCrashFile(id: UUID = UUID()) -> CrashReport? {
            let file = crashFile
            let found: (data: Data, modified: Date?)? = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                guard let data = FileManager.default.contents(atPath: file.path(percentEncoded: false)) else { return nil }
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                try? FileManager.default.removeItem(at: file)
                return (data, modified)
            }
            guard let (data, modified) = found else { return nil }
            // A file cut off inside a character isn't UTF-8; Latin-1 reads any bytes, so its
            // ASCII lines (the keys and the frames) still parse.
            let text = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
            guard let report = CrashFile.parse(text, id: id, fallbackDate: modified ?? Date()) else { return nil }
            add(report)
            return report
        }

        /// Keeps the reports `diagnostics` describe; ones whose JSON isn't a crash diagnostic are
        /// dropped.
        func receive(_ diagnostics: [CrashDiagnostic]) {
            for diagnostic in diagnostics {
                if let report = diagnostic.report(id: UUID()) {
                    add(report)
                }
            }
        }

        /// Keeps `report`, deleting the oldest past ``limit``.
        func add(_ report: CrashReport) {
            save(report)
            let sorted = (reports.filter { $0.id != report.id } + [report]).sorted(by: CrashReport.isNewer)
            for dropped in sorted.dropFirst(Self.limit) {
                removeFile(for: dropped.id)
            }
            update(Array(sorted.prefix(Self.limit)))
        }

        /// Marks the report with `id` as opened.
        func markSeen(_ id: CrashReport.ID) {
            update(reports.map { report in
                guard report.id == id, !report.isSeen else { return report }
                var seen = report
                seen.isSeen = true
                save(seen)
                return seen
            })
        }

        /// Marks every report as opened.
        func markAllSeen() {
            for report in reports where !report.isSeen {
                markSeen(report.id)
            }
        }

        /// Deletes the report with `id`.
        func delete(_ id: CrashReport.ID) {
            removeFile(for: id)
            update(reports.filter { $0.id != id })
        }

        /// Deletes every report.
        func deleteAll() {
            for report in reports {
                removeFile(for: report.id)
            }
            update([])
        }

        private func update(_ newReports: [CrashReport]) {
            reports = newReports
            onUnseenCountChange(unseenCount)
        }

        private func save(_ report: CrashReport) {
            // A report of strings, a date and a Boolean always encodes.
            if let data = try? JSONEncoder().encode(report) {
                DebugDrawerActivity.$isDrawerWork.withValue(true) {
                    try? data.write(to: file(for: report.id), options: .atomic)
                }
            }
        }

        private func removeFile(for id: CrashReport.ID) {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try? FileManager.default.removeItem(at: file(for: id))
            }
        }

        private func file(for id: CrashReport.ID) -> URL {
            directory.appending(path: "\(id.uuidString).json")
        }

        /// The reports in `directory`, newest first; a file that isn't a report is skipped.
        private static func load(from directory: URL) -> [CrashReport] {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return files
                .filter { $0.pathExtension == "json" }
                .compactMap { file in (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(CrashReport.self, from: $0) } }
                .sorted(by: CrashReport.isNewer)
        }
    }

    extension CrashReport {
        /// Whether `first` sorts before `second`: the newer first, ties by identity so the order
        /// is the same on every load.
        fileprivate static func isNewer(_ first: CrashReport, _ second: CrashReport) -> Bool {
            first.date == second.date ? first.id.uuidString < second.id.uuidString : first.date > second.date
        }
    }
#endif
