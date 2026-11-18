#if DEBUG
    import DebugDrawer
    import Foundation
    import os

    /// Pseudo-localized copies of the app's plurals, so a pseudo-localized plural still formats
    /// each count with its own variant.
    ///
    /// A lookup of a stringsdict key returns a string that carries the plural rules with it,
    /// which `String.localizedStringWithFormat` reads; a string built from it would lose them and
    /// format every count with the same words. So for each of the app's bundles with
    /// stringsdicts, a bundle is written to the temporary folder holding the same stringsdicts
    /// pseudo-localized (``PseudoLocalization/transform(stringsdictEntry:)``), and a plural key is
    /// looked up there instead, by Foundation itself.
    ///
    /// A bundle's copy is written the first time one of its plurals is pseudo-localized, under the
    /// lock: the lookups that wait for it wait once, and the copy is never written twice.
    final class PseudoPluralBundles: Sendable {
        /// The copies, for the life of the app.
        ///
        /// In a folder of the process's own: processes that share a temporary folder (a Mac app
        /// run twice, tests in parallel) would otherwise write each other's copies, and Foundation
        /// caches a bundle by its path.
        static let shared = PseudoPluralBundles(folder: FileManager.default.temporaryDirectory.appending(
            path: "DebugDrawerPseudoLocalization/\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory
        ))

        /// A bundle's pseudo-localized plurals: where the copy is, and the keys of each table it
        /// holds.
        struct Copy: Sendable {
            let url: URL
            let keys: [String: Set<String>]
        }

        private let folder: URL
        /// Each source bundle's copy by its path; `nil` for one with no plurals.
        private let copies = OSAllocatedUnfairLock<[String: Copy?]>(initialState: [:])

        init(folder: URL) {
            self.folder = folder
        }

        /// The copy of the plurals of the bundle at `path`, written now if it hasn't been, or
        /// `nil` when the bundle has no stringsdict.
        func copy(ofBundleAt path: String) -> Copy? {
            copies.withLock { copies in
                if let copy = copies[path] {
                    return copy
                }
                // The drawer's own work, which Disk I/O leaves out.
                let copy = DebugDrawerActivity.$isDrawerWork.withValue(true) { write(URL(fileURLWithPath: path), index: copies.count) }
                copies[path] = copy
                return copy
            }
        }

        /// Writes the pseudo-localized stringsdicts of the bundle at `source` into a bundle of its
        /// own, with a folder for every localization the source has, so Foundation picks the
        /// same localization in both.
        private func write(_ source: URL, index: Int) -> Copy? {
            let manager = FileManager.default
            let resources = Bundle(url: source)?.resourceURL ?? source
            let lprojs = ((try? manager.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "lproj" }
            let destination = folder.appending(path: "\(index)-\(source.lastPathComponent).bundle", directoryHint: .isDirectory)
            try? manager.removeItem(at: destination)
            var keys: [String: Set<String>] = [:]
            do {
                for lproj in lprojs {
                    let target = destination.appending(path: lproj.lastPathComponent, directoryHint: .isDirectory)
                    try manager.createDirectory(at: target, withIntermediateDirectories: true)
                    let files = try manager.contentsOfDirectory(at: lproj, includingPropertiesForKeys: nil)
                    for file in files where file.pathExtension == "stringsdict" {
                        guard let entries = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil)
                            as? [String: Any]
                        else { continue }
                        let pseudo = entries.mapValues { value in
                            (value as? [String: Any]).map(PseudoLocalization.transform(stringsdictEntry:)) ?? value
                        }
                        try PropertyListSerialization.data(fromPropertyList: pseudo, format: .binary, options: 0)
                            .write(to: target.appending(path: file.lastPathComponent))
                        keys[file.deletingPathExtension().lastPathComponent, default: []].formUnion(entries.keys)
                    }
                }
                guard !keys.isEmpty else { return nil }
                let info: [String: Any] = [
                    "CFBundleIdentifier": "debugdrawer.pseudo-plurals.\(index)",
                    "CFBundleDevelopmentRegion": Bundle(url: source)?.developmentLocalization ?? "en"
                ]
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                    .write(to: destination.appending(path: "Info.plist"))
            } catch {
                Self.logger.error("Couldn't write the pseudo-localized plurals of \(source.lastPathComponent, privacy: .public): \(error)")
                return nil
            }
            return Copy(url: destination, keys: keys)
        }

        private static let logger = Logger(subsystem: "DebugDrawerLocalizationPlugin", category: "PseudoPluralBundles")
    }
#endif
