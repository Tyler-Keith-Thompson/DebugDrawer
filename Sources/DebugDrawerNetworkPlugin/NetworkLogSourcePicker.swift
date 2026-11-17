#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Captured or Imported, above the status filter while a HAR file is imported, and the file's
    /// name and request count while its requests show.
    struct NetworkLogSourcePicker: View {
        @Binding var source: NetworkLogSource
        /// The imported file's name.
        let fileName: String
        /// How many requests the file holds.
        let count: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Requests", selection: $source) {
                    ForEach(NetworkLogSource.allCases, id: \.self) { source in
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
