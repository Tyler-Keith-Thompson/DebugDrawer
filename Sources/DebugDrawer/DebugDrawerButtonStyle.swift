import SwiftUI

/// The drawer's buttons, the push buttons of Xcode's panes: one look per kind of action, the same
/// in every plugin.
///
/// Apply one with `debugDrawerButtonStyle(_:)`, on a button or on a container to style every
/// button inside it. ``DebugDrawerActionRow`` gives its buttons ``secondary`` unless they name
/// another.
///
/// - ``primary``: the action a row exists for (Request, Send), filled with the accent color under
///   white text. One per row at most.
/// - ``secondary``: every other action (Copy, Refresh, Open Settings): a push button, its title in
///   the text color on a light face with an edge and a 1 pt shadow.
/// - ``destructive``: an action that deletes or resets: a push button with its title in the error
///   color.
/// - ``borderless``: a title or icon in the accent color with no face, for an action inside a row
///   or a header (Copy, reveal, remove one item).
/// - ``plain``: no look of its own, for a row or a label that is itself the button.
///
/// On iOS the push buttons are 36 points tall and reach a 44 point target; on the Mac, whose
/// pointer needs no such target, 22. Both grow with the text. On tvOS the modifier picks the
/// system's matching style instead, since only the system's styles show which button has focus.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerButtonStyle: ButtonStyle, Sendable {
    enum Kind: Sendable {
        case primary
        case secondary
        case destructive
        case borderless
        case plain
    }

    let kind: Kind

    /// The action a row exists for, filled with the accent color.
    public static let primary = DebugDrawerButtonStyle(kind: .primary)
    /// Any other action: a push button.
    public static let secondary = DebugDrawerButtonStyle(kind: .secondary)
    /// An action that deletes or resets: a push button titled in the error color.
    public static let destructive = DebugDrawerButtonStyle(kind: .destructive)
    /// A title or icon in the accent color with no face, for an action inside a row.
    public static let borderless = DebugDrawerButtonStyle(kind: .borderless)
    /// No look of its own, for a row or label that is itself the button.
    public static let plain = DebugDrawerButtonStyle(kind: .plain)

    public func makeBody(configuration: Configuration) -> some View {
        #if DEBUG
            DrawerButtonBody(configuration: configuration, kind: kind)
        #else
            EmptyView()
        #endif
    }
}

public extension View {
    /// Styles the buttons in this view as one of the drawer's ``DebugDrawerButtonStyle`` kinds.
    ///
    /// In release it changes nothing, so a caller compiles unchanged.
    func debugDrawerButtonStyle(_ style: DebugDrawerButtonStyle) -> some View {
        #if DEBUG && os(tvOS)
            modifier(DrawerFocusableButtonStyle(kind: style.kind))
        #elseif DEBUG
            buttonStyle(style)
        #else
            self
        #endif
    }
}

#if DEBUG
    /// A button's face: its title on the face its kind calls for, dimmed while pressed or
    /// disabled.
    struct DrawerButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: DebugDrawerButtonStyle.Kind
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.displayScale) private var displayScale
        @ScaledMetric(relativeTo: .body) private var height = DrawerSpacing.buttonHeight
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.buttonPadding
        @ScaledMetric(relativeTo: .body) private var radius = DrawerSpacing.buttonRadius

        var body: some View {
            switch kind {
            case .plain:
                configuration.label
                    .contentShape(Rectangle())
                    .opacity(configuration.isPressed ? 0.6 : 1)
            case .borderless:
                configuration.label
                    .debugDrawerFont(.body)
                    .foregroundStyle(configuration.role == .destructive ? DrawerPalette.errorText : DrawerPalette.accent)
                    .frame(minHeight: height)
                    .drawerTapTarget()
                    .opacity(opacity)
            case .primary, .secondary, .destructive:
                let shape = RoundedRectangle(cornerRadius: radius)
                configuration.label
                    .debugDrawerFont(.body)
                    .fontWeight(kind == .primary ? .semibold : .regular)
                    // A title wider than the row wraps rather than losing its end, as at
                    // accessibility sizes in a narrow panel.
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(foreground)
                    .padding(.horizontal, padding)
                    .padding(.vertical, padding / 5)
                    .frame(minHeight: height)
                    .background {
                        shape
                            .fill(fill)
                            .shadow(color: kind == .primary ? .clear : DrawerPalette.pushShadow, radius: 0, y: 1 / displayScale)
                    }
                    .overlay {
                        if kind != .primary {
                            shape.strokeBorder(DrawerPalette.pushBorder, lineWidth: 1 / displayScale)
                        }
                    }
                    .contentShape(shape)
                    .drawerTapTarget()
                    .opacity(opacity)
            }
        }

        private var opacity: Double {
            if !isEnabled { return 0.4 }
            return configuration.isPressed ? 0.6 : 1
        }

        private var foreground: Color {
            switch kind {
            case .primary: DrawerPalette.onSelection
            case .destructive: DrawerPalette.errorText
            case .secondary, .borderless, .plain: DrawerPalette.text
            }
        }

        private var fill: Color {
            kind == .primary ? DrawerPalette.selection : DrawerPalette.pushFill
        }
    }

    extension View {
        /// On a touch screen, widens what can be tapped to 44 points around the view without
        /// changing how it looks; the Mac's pointer needs no more than the view itself.
        func drawerTapTarget() -> some View {
            #if os(macOS)
                self
            #else
                padding(.vertical, 4)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -4)
            #endif
        }
    }

    #if os(tvOS)
        /// The system's style for each kind, which grows and lifts the focused button.
        struct DrawerFocusableButtonStyle: ViewModifier {
            let kind: DebugDrawerButtonStyle.Kind

            func body(content: Content) -> some View {
                switch kind {
                case .primary: content.buttonStyle(.borderedProminent)
                case .secondary: content.buttonStyle(.bordered)
                case .destructive: content.buttonStyle(.bordered).tint(.red)
                case .borderless, .plain: content.buttonStyle(.plain)
                }
            }
        }
    #endif
#endif
