#if DEBUG
    import DebugDrawer
    import MachO
    import SwiftUI

    // MARK: - Model

    private struct LoadedLibrary: Identifiable {
        let id: UInt32
        let name: String
        let path: String
        let category: LibraryCategory
    }

    private enum LibraryCategory: String, CaseIterable {
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
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lib.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                    Text(lib.path)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .textSelection(.enabled)
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
            var result: [LoadedLibrary] = []
            let count = _dyld_image_count()
            for i in 0 ..< count {
                guard let cName = _dyld_get_image_name(i) else { continue }
                let path = String(cString: cName)
                let name = (path as NSString).lastPathComponent
                let category = categorize(path: path)
                result.append(LoadedLibrary(id: i, name: name, path: path, category: category))
            }
            libraries = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        private func categorize(path: String) -> LibraryCategory {
            let systemPrefixes = [
                "/System/Library/",
                "/usr/lib/",
                "/Library/Developer/",
                "/Applications/Xcode",
            ]
            for prefix in systemPrefixes {
                if path.hasPrefix(prefix) {
                    return .system
                }
            }
            // App bundle typically contains the executable path
            if let bundlePath = Bundle.main.bundlePath as String?,
               path.hasPrefix(bundlePath)
            {
                return .app
            }
            // Anything in Frameworks within the app bundle is third-party
            if path.contains(".app/") {
                return path.contains("/Frameworks/") ? .thirdParty : .app
            }
            return .thirdParty
        }

        private func copyReport() {
            var report = "Loaded Libraries (\(libraries.count))\n"
            report += String(repeating: "=", count: 40) + "\n"
            for (cat, libs) in grouped {
                report += "\n\(cat.rawValue) (\(libs.count)):\n"
                for lib in libs {
                    report += "  \(lib.name)\n    \(lib.path)\n"
                }
            }
            debugDrawerCopyToClipboard(report)
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installLoadedLibraries() {
            registerGlobal(LoadedLibrariesPlugin())
        }
    }
#endif
