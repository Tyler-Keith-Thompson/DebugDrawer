import DebugDrawer
import MachO
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// Every image loaded into the process, grouped as App, Third-Party and System, each with its
/// path, UUID, load address and, for a framework, its version.
public struct LoadedLibrariesPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "LoadedLibrariesPlugin"
    }

    public var title = "Loaded Libraries"
    public var category = "App"
    public var icon = "books.vertical"

    public init() {}

    public var body: some View {
        #if DEBUG
            LoadedLibrariesPluginView()
        #else
            EmptyView()
        #endif
    }

    /// Has nothing to stop or drop: the plugin starts no work, and the list of images lives in
    /// its view, read each time the view appears and gone with it.
    @MainActor public func uninstall(from drawer: DebugDrawer) {}
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Loaded Libraries plugin, which reads the loaded images when its view appears.
    func installLoadedLibraries() {
        #if DEBUG
            registerGlobal(LoadedLibrariesPlugin())
        #endif
    }
}

#if DEBUG
    // MARK: - Model

    struct LoadedLibrary: Identifiable, Equatable {
        let id: UInt32
        let name: String
        let path: String
        let category: LibraryCategory
        /// The image's LC_UUID, which matches its dSYM.
        let uuid: UUID?
        /// Where the image's Mach-O header is mapped.
        let loadAddress: UInt
        /// CFBundleShortVersionString of the framework the image belongs to, if any.
        let version: String?

        var loadAddressLabel: String { String(format: "0x%llx", UInt64(loadAddress)) }

        /// Every image dyld has loaded into this process.
        static func loadAll(bundlePath: String = Bundle.main.bundlePath) -> [LoadedLibrary] {
            var result: [LoadedLibrary] = []
            for index in 0 ..< _dyld_image_count() {
                guard let cName = _dyld_get_image_name(index) else { continue }
                let path = String(cString: cName)
                let header = _dyld_get_image_header(index)
                result.append(LoadedLibrary(
                    id: index,
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    category: categorize(path: path, bundlePath: bundlePath),
                    uuid: header.flatMap(uuid(of:)),
                    loadAddress: header.map { UInt(bitPattern: $0) } ?? 0,
                    version: frameworkVersion(path: path)
                ))
            }
            return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        static func categorize(path: String, bundlePath: String) -> LibraryCategory {
            let systemPrefixes = [
                "/System/Library/",
                "/usr/lib/",
                "/Library/Developer/",
                "/Applications/Xcode"
            ]
            // The app's own bundle first: it decides, wherever the bundle lives.
            let bundle = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
            if path.hasPrefix(bundle) {
                // Embedded frameworks (<bundle>/Frameworks/, <bundle>/Contents/Frameworks/)
                // are third-party; the executable and everything else in the bundle is the app's.
                let inBundle = path.dropFirst(bundle.count)
                return inBundle.hasPrefix("Frameworks/") || inBundle.hasPrefix("Contents/Frameworks/")
                    ? .thirdParty : .app
            }
            if systemPrefixes.contains(where: path.hasPrefix) {
                return .system
            }
            return .thirdParty
        }

        /// The LC_UUID load command of the Mach-O image whose header is at `header`.
        static func uuid(of header: UnsafePointer<mach_header>) -> UUID? {
            let raw = UnsafeRawPointer(header)
            let headerSize: Int
            switch header.pointee.magic {
            case MH_MAGIC_64: headerSize = MemoryLayout<mach_header_64>.size
            case MH_MAGIC: headerSize = MemoryLayout<mach_header>.size
            default: return nil
            }
            var command = raw + headerSize
            for _ in 0 ..< header.pointee.ncmds {
                let load = command.load(as: load_command.self)
                if load.cmd == UInt32(LC_UUID) {
                    return UUID(uuid: command.load(as: uuid_command.self).uuid)
                }
                command += Int(load.cmdsize)
            }
            return nil
        }

        /// The version in the Info.plist of the `.framework` that contains `path`.
        static func frameworkVersion(path: String) -> String? {
            guard let range = path.range(of: ".framework/", options: .backwards) else { return nil }
            let frameworkPath = String(path[..<range.lowerBound]) + ".framework"
            return Bundle(path: frameworkPath)?.infoDictionary?["CFBundleShortVersionString"] as? String
        }
    }

    enum LibraryCategory: String, CaseIterable {
        case app = "App"
        case thirdParty = "Third-Party"
        case system = "System"
    }

    private struct LoadedLibrariesPluginView: View {
        @State private var libraries: [LoadedLibrary] = []
        @State private var searchText = ""
        @State private var selectedCategory: LibraryCategory?

        private var filtered: [LoadedLibrary] {
            var result = libraries
            if let cat = selectedCategory {
                result = result.filter { $0.category == cat }
            }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                result = result.filter {
                    $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query)
                }
            }
            return result
        }

        private var grouped: [(LibraryCategory, [LoadedLibrary])] {
            let dict = Dictionary(grouping: filtered, by: \.category)
            return LibraryCategory.allCases.compactMap { cat in
                guard let libs = dict[cat], !libs.isEmpty else { return nil }
                return (cat, libs)
            }
        }

        var body: some View {
            DebugDrawerRow("\(libraries.count) libraries loaded", accessory: {
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(LibraryCategory?.none)
                    ForEach(LibraryCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(LibraryCategory?.some(category))
                    }
                }
                .pickerStyle(.menu)
            })
            .onAppear { loadLibraries() }

            TextField("Filter by name or path", text: $searchText)
                .debugDrawerTextFieldStyle()
                .accessibilityLabel("Filter libraries by name or path")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.0) { category, libs in
                        DebugDrawerSection("\(category.rawValue) (\(libs.count))") {
                            ForEach(libs) { lib in
                                LoadedLibraryRow(library: lib)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy List") { report }
            }
        }

        private func loadLibraries() {
            libraries = LoadedLibrary.loadAll()
        }

        private var report: String {
            var report = "Loaded Libraries (\(libraries.count))\n"
            report += String(repeating: "=", count: 40) + "\n"
            for (cat, libs) in grouped {
                report += "\n\(cat.rawValue) (\(libs.count)):\n"
                for lib in libs {
                    report += "  \(lib.name)\(lib.version.map { " \($0)" } ?? "")\n    \(lib.path)\n"
                    report += "    UUID \(lib.uuid?.uuidString ?? "—") at \(lib.loadAddressLabel)\n"
                }
            }
            return report
        }
    }

    /// A library: its type badge (the app, a framework or a dylib), its name and version, its
    /// path cut in the middle so the file name shows, and its UUID and load address.
    struct LoadedLibraryRow: View {
        let library: LoadedLibrary

        var body: some View {
            DebugDrawerTypeBadgeRow(
                library.name,
                kind: library.badgeKind,
                path: library.path,
                detail: "\(library.uuid?.uuidString ?? "no UUID") · \(library.loadAddressLabel)",
                version: library.version
            )
        }
    }

    extension LoadedLibrary {
        /// The app's executable is the app; a binary inside a .framework bundle is a framework;
        /// anything else is a dylib.
        fileprivate var badgeKind: DebugDrawerTypeBadgeRow.Kind {
            if category == .app, !path.contains(".framework/") { return .app }
            return path.contains(".framework/") ? .framework : .dylib
        }
    }

#endif
