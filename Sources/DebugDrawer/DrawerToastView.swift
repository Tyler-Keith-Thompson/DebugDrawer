#if DEBUG
    import SwiftUI

    /// A plugin's toast: its icon, title and latest message, how many posts it stands for, a tap
    /// target that opens the drawer at the plugin, and a dismiss button whose hit area is the
    /// card's top trailing corner: 44 points square for touch, 22 on the Mac.
    struct DrawerToastView: View {
        let toast: DebugDrawerToast
        /// The plugin that raised it, if it's still registered.
        let plugin: AnyDebugDrawerPlugin?
        let open: () -> Void
        let dismiss: () -> Void
        /// Called as a hold on the toast starts (`true`) and ends (`false`), so it stays while
        /// someone points at it.
        var hold: (DrawerToastHold, Bool) -> Void = { _, _ in }
        /// Which of the toast's buttons has accessibility focus, kept by whoever shows the toast.
        ///
        /// The owner's state rather than this view's: `accessibilityFocused` leaves the view
        /// blank in an `ImageRenderer`, so a toast drawn alone (a snapshot) goes without it.
        var focusedButton: AccessibilityFocusState<FocusedButton?>.Binding?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        /// The toast's buttons, for knowing whether accessibility focus is on the toast.
        enum FocusedButton: Hashable {
            case open
            case dismiss
        }

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Button(action: open) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: plugin?.icon ?? "ladybug")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(plugin?.title ?? toast.pluginID)
                                .font(.caption.weight(.semibold))
                            Text(toast.message)
                                .font(.caption)
                                // Three lines hold only a few words at accessibility text
                                // sizes; six keep a typical message whole.
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 3)
                        }
                        Spacer(minLength: 0)
                        if toast.count > 1 {
                            Text(toast.count, format: .number)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("\(toast.count) notices")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the debug drawer at this plugin")
                .accessibilityFocused(ifBound: focusedButton, equals: .open)

                #if os(tvOS)
                    // Focus moves between the buttons on tvOS: there is no hit area to grow.
                    dismissButton {
                        dismissIcon
                    }
                #else
                    // Holds the icon's place, so the text wraps where it did; the button is drawn
                    // over the card's corner, with its larger hit area.
                    dismissIcon
                        .hidden()
                #endif
            }
            .padding(10)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            #if !os(tvOS)
                // Over the padded card, so the hit area reaches the card's edges without leaving
                // it: on iOS the toast's window takes touches only inside the card.
                .overlay(alignment: .topTrailing) {
                    dismissButton {
                        dismissIcon
                            .padding([.top, .trailing], 10)
                            .frame(minWidth: DrawerSpacing.iconButton, minHeight: DrawerSpacing.iconButton, alignment: .topTrailing)
                            .contentShape(Rectangle())
                    }
                }
            #endif
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            // Wherever a pointer can be: Mac Catalyst's falls under os(iOS) and is held the same.
            #if os(macOS) || os(iOS) || os(visionOS)
                .onHover { hold(.pointer, $0) }
            #endif
            .onDisappear { hold(.pointer, false) }
            .padding(Self.margin)
        }

        /// The dismiss button's icon, where it sits in the toast; the button carries the label.
        private var dismissIcon: some View {
            Image(systemName: "xmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }

        private func dismissButton(@ViewBuilder label: () -> some View) -> some View {
            Button(action: dismiss, label: label)
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .accessibilityFocused(ifBound: focusedButton, equals: .dismiss)
        }

        /// The clear space around the toast, from the window's edges.
        nonisolated static let margin: CGFloat = 12

        /// The widest the toast is drawn, its margin left out.
        nonisolated static let maxWidth: CGFloat = 320
    }

    extension View {
        /// Binds accessibility focus on this view to `binding`'s `value`, when there is a binding.
        @ViewBuilder
        fileprivate func accessibilityFocused<Value: Hashable>(
            ifBound binding: AccessibilityFocusState<Value?>.Binding?,
            equals value: Value
        ) -> some View {
            if let binding {
                accessibilityFocused(binding, equals: value)
            } else {
                self
            }
        }
    }
#endif
