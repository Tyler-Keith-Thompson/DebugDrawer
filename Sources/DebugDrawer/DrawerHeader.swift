#if DEBUG
    import SwiftUI

    /// The drawer's title row: its name, the Create Report button and the close button. At
    /// accessibility text sizes the title and the buttons don't share a line, so the buttons sit on
    /// a line below the title.
    struct DrawerHeader: View {
        /// A report is being written or sent, so another can't be started.
        let isReportInProgress: Bool
        let createReport: () -> Void
        let close: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 0) {
                        title
                        HStack {
                            Spacer()
                            buttons
                        }
                    }
                } else {
                    HStack {
                        title
                        Spacer()
                        buttons
                    }
                }
            }
            // The buttons' 44 pt targets supply the header's height and trailing margin.
            .padding(.leading, 14)
            .padding(.trailing, 2)
            #if os(tvOS)
                // A focused button grows and lifts on a platter; the space keeps it inside the
                // panel and off the search field.
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            #endif
        }

        private var title: some View {
            HStack {
                Image(systemName: "ladybug")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Debug")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
        }

        @ViewBuilder
        private var buttons: some View {
            Button(action: createReport) {
                Image(systemName: "doc.zipper")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .frame(minWidth: DrawerCloseButton.minimumTapSize, minHeight: DrawerCloseButton.minimumTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isReportInProgress)
            .accessibilityLabel("Create a bug report")
            .help("Create a bug report")
            DrawerCloseButton(action: close)
        }
    }
#endif
