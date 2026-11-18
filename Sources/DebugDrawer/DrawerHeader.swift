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
        /// The plugin shown alone, which the jump bar's path ends at and the back button leaves;
        /// `nil` in the outline.
        var focus: AnyDebugDrawerPlugin?
        /// The plugins the jump bar's menu lists, grouped as the outline groups them; with none,
        /// the jump bar is no menu.
        var sections: [DrawerSection]
        /// Shows the outline, or a plugin alone.
        let navigate: (DrawerNavigation) -> Void
        let createReport: () -> Void
        let close: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var inset = DrawerSpacing.panelInset
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap

        init(
            isReportInProgress: Bool,
            context: DrawerJumpBar.Context? = nil,
            focus: AnyDebugDrawerPlugin? = nil,
            sections: [DrawerSection] = [],
            navigate: @escaping (DrawerNavigation) -> Void = { _ in },
            createReport: @escaping () -> Void,
            close: @escaping () -> Void
        ) {
            self.isReportInProgress = isReportInProgress
            self.context = context
            self.focus = focus
            self.sections = sections
            self.navigate = navigate
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
                if let context {
                    HStack(spacing: gap / 2) {
                        if focus != nil {
                            // Xcode's back arrow, at the jump bar's leading end.
                            Button { navigate(.outline) } label: {
                                DrawerIconButtonLabel(systemImage: "chevron.backward")
                            }
                            .debugDrawerButtonStyle(.plain)
                            .accessibilityLabel("Back to all plugins")
                            .help("Back to all plugins")
                        }
                        jumpBar(context)
                    }
                }
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

        /// The jump bar, which, as Xcode's does, opens a menu of the places it can go: every plugin
        /// by section, each shown alone, and All Plugins, the outline.
        @ViewBuilder
        private func jumpBar(_ context: DrawerJumpBar.Context) -> some View {
            let bar = DrawerJumpBar(context: context, focus: focus)
            if sections.isEmpty {
                bar
            } else {
                Menu {
                    Button("All Plugins", systemImage: "square.grid.2x2") { navigate(.outline) }
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.plugins) { plugin in
                                Button(plugin.title, systemImage: plugin.icon) { navigate(.plugin(plugin.id)) }
                            }
                        }
                    }
                } label: {
                    bar
                }
                .menuStyle(.button)
                .debugDrawerButtonStyle(.plain)
                #if os(macOS)
                    .menuIndicator(.hidden)
                #endif
                .accessibilityHint("Shows a plugin alone.")
            }
        }

        private var title: some View {
            Text("Debug")
                .font(DebugDrawerTextStyle.panelTitle)
                .foregroundStyle(DrawerPalette.text)
                .accessibilityAddTraits(.isHeader)
        }
    }
#endif
