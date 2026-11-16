#if DEBUG
    /// What one row of the Tweaks plugin shows: a tweak's control and current value, or an
    /// action's button.
    struct TweakRowState: Identifiable {
        enum Control {
            case toggle(Bool)
            case picker(options: [TweakOption], selection: TweakStoredValue)
            case text(String)
            case stepper(Int, range: ClosedRange<Int>, step: Int)
            case action(@MainActor @Sendable () -> Void)
        }

        /// The tweak's key, or the action's section and title.
        let id: String
        let title: String
        let control: Control
        /// Whether the tweak reads other than its default, so it can be reset. Never for an action.
        let isModified: Bool
    }

    /// A section of the Tweaks plugin: its heading and rows.
    struct TweakSectionState: Identifiable {
        let title: String
        let rows: [TweakRowState]

        var id: String { title }
    }

    extension TweakSectionState {
        /// `section`'s rows, each tweak showing the value `stored` holds for its key (its default
        /// when that isn't one of its values).
        init(_ section: TweakSection, stored: (String) -> TweakStoredValue?) {
            title = section.title
            rows = section.items.map { item in
                switch item.kind {
                case let .tweak(tweak):
                    let value = tweak.resolve(stored(tweak.key))
                    return TweakRowState(
                        id: tweak.key,
                        title: tweak.title,
                        control: TweakRowState.Control(tweak.control, value: value),
                        isModified: value != tweak.defaultValue
                    )
                case let .action(action):
                    return TweakRowState(
                        id: "\(section.title).\(action.title)",
                        title: action.title,
                        control: .action(action.perform),
                        isModified: false
                    )
                }
            }
        }
    }

    extension TweakRowState.Control {
        /// `control` showing `value`, which `AnyTweak.resolve` made one of the control's values.
        fileprivate init(_ control: TweakControl, value: TweakStoredValue) {
            switch control {
            case .toggle:
                self = .toggle(value.bool ?? false)
            case let .picker(options):
                self = .picker(options: options, selection: value)
            case .text:
                self = .text(value.string ?? "")
            case let .stepper(range, step):
                self = .stepper(value.int ?? range.lowerBound, range: range, step: step)
            }
        }
    }
#endif
