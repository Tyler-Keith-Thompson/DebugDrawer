#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The libraries under a section per category, in a list that scrolls once it is taller than
    /// its cap.
    struct LoadedLibraryList: View {
        let libraries: [LoadedLibrary]
        /// The tallest the list grows before it scrolls; scales with Dynamic Type, as its rows do.
        @ScaledMetric(relativeTo: .body) private var listHeight: CGFloat = 300

        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(libraries.byCategory, id: \.0) { category, libs in
                        DebugDrawerSection("\(category.rawValue) (\(libs.count))") {
                            ForEach(libs) { lib in
                                LoadedLibraryRow(library: lib)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: listHeight)
        }
    }

    extension [LoadedLibrary] {
        /// The libraries by category, in `LibraryCategory`'s order, leaving out empty categories.
        var byCategory: [(LibraryCategory, [LoadedLibrary])] {
            let dict = Dictionary(grouping: self, by: \.category)
            return LibraryCategory.allCases.compactMap { cat in
                guard let libs = dict[cat], !libs.isEmpty else { return nil }
                return (cat, libs)
            }
        }
    }
#endif
