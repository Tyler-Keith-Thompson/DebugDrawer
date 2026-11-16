#if DEBUG
    import SwiftUI

    /// The open drawer's keyboard shortcuts, as hidden buttons. The drawer shows them only while it
    /// is open, so none of them opens it or takes a key from the app while it is closed (N2).
    struct DrawerKeyboardShortcuts: View {
        /// Whether Escape closes the drawer. False while the search field holds text, which Escape
        /// clears first.
        let closesOnEscape: Bool
        let search: () -> Void
        let nextPlugin: () -> Void
        let previousPlugin: () -> Void
        let close: () -> Void

        var body: some View {
            ForEach(commands, id: \.self) { command in
                Button(command.title) { perform(command) }
                    .keyboardShortcut(command.shortcut)
                    .hidden()
            }
        }

        private var commands: [Command] {
            Command.allCases.filter { $0 != .close || closesOnEscape }
        }

        private func perform(_ command: Command) {
            switch command {
            case .search: search()
            case .nextPlugin: nextPlugin()
            case .previousPlugin: previousPlugin()
            case .close: close()
            }
        }

        /// The plugin `step` places after `current` in `order`, held at the first and last; `nil`
        /// when `order` is empty. A `current` that isn't in `order`, or `nil`, counts as the first.
        ///
        /// - Complexity: O(*n*) in the number of plugins.
        static func plugin(by step: Int, from current: String?, in order: [String]) -> String? {
            guard !order.isEmpty else { return nil }
            let index = current.flatMap { order.firstIndex(of: $0) } ?? 0
            return order[min(max(index + step, 0), order.count - 1)]
        }
    }

    extension DrawerKeyboardShortcuts {
        /// What a shortcut does, with its key.
        enum Command: CaseIterable {
            case search, nextPlugin, previousPlugin, close

            var title: String {
                switch self {
                case .search: "Search Plugins"
                case .nextPlugin: "Next Plugin"
                case .previousPlugin: "Previous Plugin"
                case .close: "Close the debug drawer"
                }
            }

            /// Cmd-Option with the arrows moves between plugins: apps rarely bind it, while Cmd-[ and
            /// Cmd-] are Back and Forward in many. Escape is the cancel action.
            var shortcut: KeyboardShortcut {
                switch self {
                case .search: KeyboardShortcut("k", modifiers: .command)
                case .nextPlugin: KeyboardShortcut(.downArrow, modifiers: [.command, .option])
                case .previousPlugin: KeyboardShortcut(.upArrow, modifiers: [.command, .option])
                case .close: .cancelAction
                }
            }
        }
    }
#endif
