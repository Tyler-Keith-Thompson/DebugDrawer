#if DEBUG
    import Foundation

    extension DebugDrawerReport {
        /// Thrown when the report can't be written or zipped; nothing is left in the destination.
        public struct WriteFailed: Error, Equatable {}

        /// The report of every plugin in `plugins` that adopts ``DebugDrawerReportContributor``,
        /// each in a folder named after its title; the others are left out.
        @MainActor init(contributionsOf plugins: [AnyDebugDrawerPlugin], redaction: DebugDrawerRedaction) {
            self.init()
            for plugin in plugins where plugin.contributesToReport {
                var contribution = DebugDrawerReport()
                plugin.contribute(to: &contribution, redaction: redaction)
                guard !contribution.files.isEmpty else { continue }
                add(contribution, inFolder: plugin.title)
            }
        }

        /// Writes the report, with `summary.txt` at its root, to a folder named
        /// the summary's `folderName`, zips it and puts the zip in `directory`.
        ///
        /// A zip of the same name already in `directory` is replaced.
        ///
        /// - Returns: The zip's URL.
        /// - Throws: `WriteFailed` when a file can't be written or the folder can't be zipped.
        func writeArchive(summary: ReportSummary, in directory: URL) throws(WriteFailed) -> URL {
            let fileManager = FileManager.default
            let staging = fileManager.temporaryDirectory
                .appendingPathComponent("DebugDrawerReport-\(UUID().uuidString)", isDirectory: true)
            let folder = staging.appendingPathComponent(summary.folderName, isDirectory: true)
            let destination = directory.appendingPathComponent(summary.folderName).appendingPathExtension("zip")
            defer { try? fileManager.removeItem(at: staging) }
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data(summary.text(listing: self).utf8).write(to: folder.appendingPathComponent("summary.txt"))
                for file in files {
                    let url = folder.appendingPathComponent(file.path)
                    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try file.data.write(to: url)
                }
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw WriteFailed()
            }
            // Reading a folder for uploading hands the block a zip of it, Apple's own archiver, so
            // the report needs no zip package. The zip is deleted when the block returns.
            var coordinationError: NSError?
            var moved = false
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zip in
                try? fileManager.removeItem(at: destination)
                moved = (try? fileManager.moveItem(at: zip, to: destination)) != nil
            }
            guard coordinationError == nil, moved else { throw WriteFailed() }
            return destination
        }
    }
#endif
