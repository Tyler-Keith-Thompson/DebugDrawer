#if DEBUG
    import DebugDrawer
    import MachO
    import SwiftUI

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
            for i in 0 ..< _dyld_image_count() {
                guard let cName = _dyld_get_image_name(i) else { continue }
                let path = String(cString: cName)
                let header = _dyld_get_image_header(i)
                result.append(LoadedLibrary(
                    id: i,
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
                "/Applications/Xcode",
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

        var icon: String {
            switch self {
            case .app: return "app"
            case .thirdParty: return "shippingbox"
            case .system: return "gearshape"
            }
        }
    }

    // MARK: - Plugin

    public struct LoadedLibrariesPlugin: DebugDrawerPlugin {
        public var title = "Loaded Libraries"
        public var icon = "books.vertical"

        public init() {}

        public var body: some View {
            LoadedLibrariesPluginView()
        }
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
            VStack(alignment: .leading, spacing: 6) {
                // Counts
                HStack {
                    Text("\(libraries.count) libraries loaded")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy") { copyReport() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }

                // Category filter
                HStack(spacing: 4) {
                    categoryButton(nil, label: "All")
                    ForEach(LibraryCategory.allCases, id: \.self) { cat in
                        categoryButton(cat, label: cat.rawValue)
                    }
                }

                // Search
                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))

                Divider()

                // Grouped list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(grouped, id: \.0) { category, libs in
                            HStack {
                                Image(systemName: category.icon)
                                    .font(.caption2)
                                Text("\(category.rawValue) (\(libs.count))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                            ForEach(libs) { lib in
                                LoadedLibraryRow(library: lib)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .onAppear { loadLibraries() }
        }

        private func categoryButton(_ cat: LibraryCategory?, label: String) -> some View {
            Button(label) { selectedCategory = cat }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(selectedCategory == cat ? .accentColor : .secondary)
        }

        private func loadLibraries() {
            libraries = LoadedLibrary.loadAll()
        }

        private func copyReport() {
            var report = "Loaded Libraries (\(libraries.count))\n"
            report += String(repeating: "=", count: 40) + "\n"
            for (cat, libs) in grouped {
                report += "\n\(cat.rawValue) (\(libs.count)):\n"
                for lib in libs {
                    report += "  \(lib.name)\(lib.version.map { " \($0)" } ?? "")\n    \(lib.path)\n"
                    report += "    UUID \(lib.uuid?.uuidString ?? "—") at \(lib.loadAddressLabel)\n"
                }
            }
            debugDrawerCopyToClipboard(report)
        }
    }

    struct LoadedLibraryRow: View {
        let library: LoadedLibrary

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(library.name)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                    if let version = library.version {
                        Text(version)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(library.path)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(library.uuid?.uuidString ?? "no UUID") · \(library.loadAddressLabel)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .textSelection(.enabled)
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installLoadedLibraries() {
            registerGlobal(LoadedLibrariesPlugin())
        }
    }
#endif
