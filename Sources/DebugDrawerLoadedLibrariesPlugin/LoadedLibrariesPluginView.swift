#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the count and category picker, the filter, the libraries it shows and
    /// Copy List. Reads the loaded images each time it appears.
    ///
    /// It draws ``LoadedLibrariesModel``'s snapshots from its transport and sends it what the user
    /// does; Copy List, which writes the clipboard, stays here.
    struct LoadedLibrariesPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<LoadedLibrariesSnapshot, LoadedLibrariesCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<LoadedLibrariesSnapshot, LoadedLibrariesCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            DebugDrawerRow("\(snapshot.libraries.count) libraries loaded", accessory: {
                Picker("Category", selection: category) {
                    Text("All").tag(LibraryCategory?.none)
                    ForEach(LibraryCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(LibraryCategory?.some(category))
                    }
                }
                .pickerStyle(.menu)
            })
            .onAppear { transport.send(LoadedLibrariesCommand(.refresh)) }

            TextField("Filter by name or path", text: filter)
                .debugDrawerTextFieldStyle()
                .accessibilityLabel("Filter libraries by name or path")

            LoadedLibraryList(libraries: snapshot.shownLibraries)

            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy List") { transport.snapshot.report }
            }
        }

        /// The filter, read from the snapshot and changed through the model.
        private var filter: Binding<String> {
            Binding(
                get: { transport.snapshot.filter },
                set: { transport.send(LoadedLibrariesCommand(.setFilter($0))) }
            )
        }

        /// The category picked, read from the snapshot and changed through the model.
        private var category: Binding<LibraryCategory?> {
            Binding(
                get: { transport.snapshot.category },
                set: { transport.send(LoadedLibrariesCommand(.setCategory($0))) }
            )
        }
    }

    extension LoadedLibrariesSnapshot {
        /// Copy List's text: how many libraries are loaded, then the ones shown, by category, each
        /// with its version, path, UUID and load address.
        fileprivate var report: String {
            var report = "Loaded Libraries (\(libraries.count))\n"
            report += String(repeating: "=", count: 40) + "\n"
            for (cat, libs) in shownLibraries.byCategory {
                report += "\n\(cat.rawValue) (\(libs.count)):\n"
                for lib in libs {
                    report += "  \(lib.name)\(lib.version.map { " \($0)" } ?? "")\n    \(lib.path)\n"
                    report += "    UUID \(lib.uuid?.uuidString ?? "—") at \(lib.loadAddressLabel)\n"
                }
            }
            return report
        }
    }
#endif
