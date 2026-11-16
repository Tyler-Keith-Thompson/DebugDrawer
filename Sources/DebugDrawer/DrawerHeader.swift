// watchOS has no panel header; its drawer is a navigation list (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    /// The drawer's title row: "Debug", then the Create Report and close buttons as plain icons,
    /// as Xcode's panes carry their buttons; below it, the jump bar saying what is being
    /// debugged. At accessibility text sizes the title takes a line of its own below the
    /// buttons, so the word never breaks.
    struct DrawerHeader: View {
        /// A report is being written or sent, so another can't be started.
        let isReportInProgress: Bool
        /// The app, build, device and system for the jump bar; `nil` for none.
        var context: DrawerJumpBar.Context?
        let createReport: () -> Void
        let close: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var inset = DrawerSpacing.panelInset
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap

        init(
            isReportInProgress: Bool,
            context: DrawerJumpBar.Context? = nil,
            createReport: @escaping () -> Void,
            close: @escaping () -> Void
        ) {
            self.isReportInProgress = isReportInProgress
            self.context = context
            self.createReport = createReport
            self.close = close
        }

        var body: some View {
            // At accessibility sizes the title takes a line below the buttons, so the word
            // never breaks.
            let stacked = dynamicTypeSize.isAccessibilitySize
            VStack(alignment: .leading, spacing: gap / 2) {
                HStack(spacing: 0) {
                    if !stacked { title }
                    Spacer(minLength: gap)
                    Button(action: createReport) {
                        DrawerIconButtonLabel(systemImage: "ladybug")
                    }
                    .debugDrawerButtonStyle(.plain)
                    .disabled(isReportInProgress)
                    .accessibilityLabel("Create a bug report")
                    .help("Create a bug report")
                    DrawerCloseButton(action: close)
                }
                if stacked { title }
                #if !os(watchOS)
                    if let context {
                        DrawerJumpBar(context: context)
                    }
                #endif
            }
            .padding(.horizontal, inset)
            .padding(.top, gap / 2)
            #if os(tvOS)
                // A focused button grows and lifts on a platter; the space keeps it inside the
                // panel.
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            #endif
        }

        private var title: some View {
            Text("Debug")
                .font(DebugDrawerTextStyle.panelTitle)
                .foregroundStyle(DrawerPalette.text)
                .accessibilityAddTraits(.isHeader)
        }
    }
#endif
