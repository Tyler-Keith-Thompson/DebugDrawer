#if DEBUG
    /// A value read as a figure and its unit: "63.5 MB" is 63.5 and " MB", "11s" is 11 and "s".
    struct Measure: Equatable {
        let figure: String
        let unit: String

        /// The figure and unit of `value`, or `nil` unless it is digits (with an optional sign,
        /// separators and decimal point) followed by a unit of up to four letters, `%` or `µ`.
        init?(_ value: String) {
            guard let match = value.wholeMatch(of: /([-+]?[0-9][0-9.,]*)( ?[A-Za-zµ%]{1,4})/) else { return nil }
            figure = String(match.1)
            unit = String(match.2)
        }
    }
#endif
