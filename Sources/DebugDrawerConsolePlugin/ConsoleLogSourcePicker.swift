#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Captured or Previous, above the toolbar while an earlier launch's session is kept.
    struct ConsoleLogSourcePicker: View {
        @Binding var source: ConsoleLogSource

        var body: some View {
            Picker("Lines", selection: $source) {
                ForEach(ConsoleLogSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Lines")
            .accessibilityElement(children: .contain)
            .padding(.top, 8)
        }
    }
#endif
