// watchOS has no filter bar; its drawer is a navigation list (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    /// The bar pinned at the drawer's foot, above a hairline: the filter field, then the scope
    /// toggles, icon-only, the active ones on the soft selection with an accent symbol.
    struct DrawerFilterBar<Field: View>: View {
        let field: Field
        @Binding var showsOnlyOwnCode: Bool
        @Binding var showsOnlyUnread: Bool
        @ScaledMetric(relativeTo: .body) private var inset = DrawerSpacing.panelInset
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap

        init(@ViewBuilder field: () -> Field, showsOnlyOwnCode: Binding<Bool>, showsOnlyUnread: Binding<Bool>) {
            self.field = field()
            _showsOnlyOwnCode = showsOnlyOwnCode
            _showsOnlyUnread = showsOnlyUnread
        }

        var body: some View {
            HStack(spacing: gap / 2) {
                field
                DrawerScopeToggle(title: "Show only my code", systemImage: "person.crop.square", isOn: $showsOnlyOwnCode)
                DrawerScopeToggle(title: "Show only unread", systemImage: "circlebadge", isOn: $showsOnlyUnread)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, gap)
            .overlay(alignment: .top) { DrawerRule() }
        }
    }

    /// One of the filter bar's scope toggles: a symbol in a square, on the soft selection with an
    /// accent symbol while on.
    struct DrawerScopeToggle: View {
        let title: String
        let systemImage: String
        @Binding var isOn: Bool
        @ScaledMetric(relativeTo: .body) private var size = DrawerSpacing.fieldHeight

        var body: some View {
            Button {
                isOn.toggle()
            } label: {
                Image(systemName: systemImage)
                    .debugDrawerFont(.body)
                    .foregroundStyle(isOn ? DrawerPalette.accent : DrawerPalette.secondaryText)
                    .frame(minWidth: size, minHeight: size)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: DrawerSpacing.tabRadius).fill(DrawerPalette.softSelection)
                        }
                    }
                    .contentShape(Rectangle())
                    .drawerTapTarget()
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .help(title)
        }
    }
#endif
