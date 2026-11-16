#if DEBUG
    import Foundation

    /// What one row of the Feature Flags plugin shows: a flag, its live value, the control that
    /// overrides it, and its override.
    struct FeatureFlagRowState: Identifiable, Equatable {
        /// How the row edits the flag, by its live value's kind, showing the value the app reads.
        enum Control: Equatable {
            case toggle(Bool)
            case number(Double)
            case text(String)
        }

        /// The flag's key.
        let id: String
        let title: String
        let detail: String?
        let liveValue: FeatureFlagValue
        let control: Control
        /// The stored override, if any; it may be of another kind than the live value, when the
        /// flag's type changed since it was set.
        let override: FeatureFlagValue?

        var isOverridden: Bool {
            override != nil
        }
    }

    extension FeatureFlagRowState {
        /// `flag`'s row. The control shows `currentValue`, what the app reads, falling back to
        /// `override` and then the live value when the provider gives none, or one of another
        /// kind than the live value.
        init(_ flag: FeatureFlag, currentValue: FeatureFlagValue?, override: FeatureFlagValue?) {
            id = flag.key
            title = flag.title ?? flag.key
            detail = flag.detail
            liveValue = flag.liveValue
            self.override = override
            let shown = [currentValue, override].compactMap(\.self).first { $0.isSameKind(as: flag.liveValue) }
            control = Control(shown ?? flag.liveValue)
        }

        /// Whether `query` is empty or is in the row's key, title or detail, ignoring case and
        /// diacritics.
        func matches(_ query: String) -> Bool {
            let query = query.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return true }
            return [id, title, detail ?? ""].contains { $0.localizedStandardContains(query) }
        }
    }

    extension FeatureFlagRowState.Control {
        fileprivate init(_ value: FeatureFlagValue) {
            switch value {
            case let .bool(value): self = .toggle(value)
            case let .number(value): self = .number(value)
            case let .string(value): self = .text(value)
            }
        }
    }

    extension FeatureFlagValue {
        fileprivate func isSameKind(as other: FeatureFlagValue) -> Bool {
            switch (self, other) {
            case (.bool, .bool), (.number, .number), (.string, .string): true
            default: false
            }
        }
    }

    /// What the Feature Flags plugin lists: nothing to show, nothing matching the search or the
    /// filter, or the matching flags.
    enum FeatureFlagList: Equatable {
        /// The provider lists no flags.
        case noFlags
        /// No flag matches the search, or none is overridden while only overridden ones are shown.
        case noMatches
        case flags([FeatureFlagRowState])

        /// `rows` filtered by `query` and, when `overriddenOnly`, to overridden flags.
        init(_ rows: [FeatureFlagRowState], query: String, overriddenOnly: Bool) {
            guard !rows.isEmpty else {
                self = .noFlags
                return
            }
            let matching = rows.filter { (!overriddenOnly || $0.isOverridden) && $0.matches(query) }
            self = matching.isEmpty ? .noMatches : .flags(matching)
        }
    }
#endif
