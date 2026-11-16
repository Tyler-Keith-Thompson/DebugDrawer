#if DEBUG
    import SwiftUI

    /// The drawer's title row: its name, the Create Report button and the close button.
    struct DrawerHeader: View {
        /// A report is being written, so another can't be started.
        let isCreatingReport: Bool
        let createReport: () -> Void
        let close: () -> Void

        var body: some View {
            HStack {
                Image(systemName: "ladybug")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Debug")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: createReport) {
                    Image(systemName: "doc.zipper")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                        .frame(minWidth: DrawerCloseButton.minimumTapSize, minHeight: DrawerCloseButton.minimumTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCreatingReport)
                .accessibilityLabel("Create a bug report")
                .help("Create a bug report")
                DrawerCloseButton(action: close)
            }
            // The buttons' 44 pt targets supply the header's height and trailing margin.
            .padding(.leading, 14)
            .padding(.trailing, 2)
        }
    }
#endif
