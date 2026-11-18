// watchOS lists the plugins in a navigation list instead (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    /// One plugin in the drawer's outline: its header row and, while expanded, its body set in
    /// past the disclosure triangle, with a hairline below, as a group in Xcode's navigators.
    struct DrawerPluginSection<Header: View>: View {
        let plugin: AnyDebugDrawerPlugin
        let isExpanded: Bool
        let header: Header
        @ScaledMetric(relativeTo: .body) private var scaledIndent = DrawerSpacing.contentIndent
        @ScaledMetric(relativeTo: .body) private var scaledInset = DrawerSpacing.panelInset
        // The indent and margins grow with the text only a little: at accessibility sizes the
        // panel's width is better spent on the text.
        private var indent: CGFloat { min(scaledIndent, DrawerSpacing.contentIndent * 1.25) }
        private var inset: CGFloat { min(scaledInset, DrawerSpacing.panelInset * 1.25) }
        @ScaledMetric(relativeTo: .body) private var bottom = DrawerSpacing.rowPadding
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        /// Shows the plugin alone, from a button at the header's trailing end; `nil` for no button.
        let showAlone: (() -> Void)?

        init(plugin: AnyDebugDrawerPlugin, isExpanded: Bool, showAlone: (() -> Void)? = nil, @ViewBuilder header: () -> Header) {
            self.plugin = plugin
            self.isExpanded = isExpanded
            self.showAlone = showAlone
            self.header = header()
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    headerBlock
                    if let showAlone {
                        Button(action: showAlone) {
                            DrawerIconButtonLabel(systemImage: "chevron.forward")
                        }
                        .debugDrawerButtonStyle(.plain)
                        .accessibilityLabel("Show \(plugin.title) alone")
                        .help("Show \(plugin.title) alone")
                        .padding(.trailing, inset / 2)
                    }
                }
                if isExpanded {
                    // A stack of its own, so a body of several views is laid out as one rather
                    // than each view taking the padding below on its own.
                    VStack(alignment: .leading, spacing: 0) {
                        plugin.body
                    }
                    .debugDrawerFont(.body)
                    .foregroundStyle(DrawerPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, inset + indent)
                    .padding(.trailing, inset)
                    .padding(.bottom, bottom)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                DrawerRule()
            }
        }

        /// The header and its accessory. The accessory sits beside the header's button rather than
        /// in it, so an action in it is a control of its own and VoiceOver reads it apart from the
        /// heading. It goes under the header, where the title has the row's width to itself, at
        /// accessibility text sizes and whenever the title and the accessory are too wide to share
        /// the row.
        @ViewBuilder private var headerBlock: some View {
            if let accessory = plugin.headerAccessory {
                if dynamicTypeSize.isAccessibilitySize {
                    headerRow(accessory, below: true)
                } else {
                    ViewThatFits(in: .horizontal) {
                        headerRow(accessory, below: false)
                        headerRow(accessory, below: true)
                    }
                }
            } else {
                header
            }
        }

        /// The header with `accessory` beside it, or under it, set in to where the body starts.
        private func headerRow(_ accessory: AnyView, below: Bool) -> some View {
            let layout = below
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))
            return layout {
                header
                accessory
                    .debugDrawerFont(.code)
                    .foregroundStyle(DrawerPalette.tertiaryText)
                    .debugDrawerButtonStyle(.borderless)
                    // Beside the title, its ideal size, so it never wraps; the title wraps instead.
                    // Under it, the row's width, so one wider than the drawer gives way (a
                    // ViewThatFits in it picks a shorter form) rather than push the title off.
                    .fixedSize(horizontal: !below, vertical: true)
                    .padding(.leading, below ? inset + indent : 0)
                    .padding(.trailing, inset)
            }
        }
    }

    extension View {
        /// The open drawer's panel: one flat surface, with a hairline along its edge and a light
        /// shadow to lift it off the app; on tvOS, whose panel sits over the app across a room, a
        /// thick material.
        func drawerPanelSurface() -> some View {
            modifier(DrawerPanelSurface())
        }
    }

    /// The look `drawerPanelSurface()` gives the panel.
    private struct DrawerPanelSurface: ViewModifier {
        @Environment(\.displayScale) private var displayScale

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: 10)
            #if os(tvOS)
                content
                    .background(.ultraThickMaterial)
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.25), radius: 12, x: -4)
            #elseif os(macOS)
                // The panel fills a window of its own, which draws the shadow around it
                // (DrawerChildPanel): one drawn here would be clipped at the window's edges.
                content
                    .background(DrawerPalette.panel)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(DrawerPalette.separator, lineWidth: 1 / displayScale) }
            #else
                content
                    .background(DrawerPalette.panel)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(DrawerPalette.separator, lineWidth: 1 / displayScale) }
                    .shadow(color: .black.opacity(0.15), radius: 6, x: -2)
            #endif
        }
    }
#endif
