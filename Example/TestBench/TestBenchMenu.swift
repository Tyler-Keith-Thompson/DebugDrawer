#if os(macOS)
    import AppKit

    /// The test bench as a Mac menu: a submenu per plugin and an item per action, for the menu bar.
    @MainActor
    public enum TestBenchMenu {
        /// A "Test Bench" menu; each item runs its action and hands what it did to `report`.
        public static func make(report: @escaping @MainActor (TestBenchAction, String) -> Void) -> NSMenu {
            let menu = NSMenu(title: "Test Bench")
            for section in TestBench.sections {
                let submenu = NSMenu(title: section.plugin)
                for action in section.actions {
                    submenu.addItem(TestBenchMenuItem(action, report: report))
                }
                menu.addItem(withTitle: section.plugin, action: nil, keyEquivalent: "").submenu = submenu
            }
            return menu
        }
    }

    /// A menu item that runs one action, its own target.
    private final class TestBenchMenuItem: NSMenuItem {
        private let testBenchAction: TestBenchAction
        private let report: @MainActor (TestBenchAction, String) -> Void

        init(_ action: TestBenchAction, report: @escaping @MainActor (TestBenchAction, String) -> Void) {
            testBenchAction = action
            self.report = report
            super.init(title: action.title, action: #selector(run), keyEquivalent: "")
            target = self
        }

        // Made in code only; a nib never holds one, so this never runs.
        @available(*, unavailable)
        required init(coder _: NSCoder) {
            fatalError("TestBenchMenuItem is made in code")
        }

        @objc private func run() {
            let action = testBenchAction
            let report = report
            Task { @MainActor in
                let outcome = await action.run()
                report(action, outcome)
            }
        }
    }
#endif
