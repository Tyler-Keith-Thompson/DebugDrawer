#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Captured, Previous or Imported, above the status filter while an earlier launch's session
    /// is kept or a HAR file is imported, and the file's name and request count while its
    /// requests show.
    struct NetworkLogSourcePicker: View {
        @Binding var source: NetworkLogSource
        /// The imported file's name, shown while `source` is `.imported`.
        let fileName: String
        /// How many requests the file holds.
        let count: Int
        /// The segments, in order: the sources that have something to show.
        var sources: [NetworkLogSource] = [.captured, .imported]

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Requests", selection: $source) {
                    ForEach(sources, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Requests")
                .accessibilityElement(children: .contain)
                .padding(.top, 8)
                if source == .imported {
                    DebugDrawerKeyValueRow("File", value: fileName)
                        .debugDrawerValueStyle(.text)
                    DebugDrawerKeyValueRow("Requests", value: "\(count.formatted()), read-only")
                        .debugDrawerValueStyle(.text)
                }
            }
        }
    }
#endif
