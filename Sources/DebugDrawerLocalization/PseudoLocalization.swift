import Foundation

// Real in every build: the drawer's live mode and the receiver's localization review both draw
// strings with it.

/// The pseudo-localization of a string: the same text with its ASCII letters accented, padded
/// about 40% longer and set in brackets, `Settings` becoming `[Šéţţîñĝš····]`. It reads
/// almost as the original does, yet shows text the app never localized (no accents), text
/// clipped by a layout too tight for a longer language (a missing `]` or padding), and text
/// joined from pieces (brackets in the middle).
///
/// The transform is deterministic, and leaves format specifiers (`%@`, `%1$lld`, `%%`) and
/// stringsdict variables (`%#@items@`) as they are, so the string still formats with the
/// same arguments.
package enum PseudoLocalization {
    /// The character the padding is drawn with.
    package static let padding: Character = "·"

    /// `text` pseudo-localized: each ASCII letter accented, then `ceil(0.4 × n)` padding
    /// characters, where *n* counts the characters outside format specifiers, and the whole
    /// in brackets. The empty string stays empty, so a view that hides an empty label still
    /// does.
    ///
    /// - Parameter isBracketed: Whether to add the brackets and the padding; `false` only
    ///   accents, for the parts of a plural that a bracketed format string holds.
    /// - Complexity: O(*n*), where *n* is the length of `text`.
    package static func transform(_ text: String, isBracketed: Bool = true) -> String {
        guard !text.isEmpty else { return text }
        var accented = ""
        var literalCount = 0
        for token in text.formatTokens {
            switch token {
            case let .literal(literal):
                literalCount += literal.count
                accented.append(contentsOf: literal.map(\.accented))
            case let .specifier(specifier):
                accented.append(specifier)
            }
        }
        guard isBracketed else { return accented }
        // 40% is the growth to plan for between English and the longer European languages
        // (German, Finnish); rounded up, so even one letter gets one.
        let paddingCount = (literalCount * 2 + 4) / 5
        return "[" + accented + String(repeating: padding, count: paddingCount) + "]"
    }

    /// A stringsdict entry pseudo-localized: its format string (`NSStringLocalizedFormatKey`)
    /// bracketed and padded, and every plural or device variant accented, so whichever
    /// variant formats, the result is bracketed once. The rule and value types
    /// (`NSStringFormatSpecTypeKey`, `NSStringFormatValueTypeKey`) stay as they are.
    package static func transform(stringsdictEntry entry: [String: Any]) -> [String: Any] {
        entry.reduce(into: [:]) { result, element in
            let (key, value) = element
            switch value {
            case let text as String where key == "NSStringLocalizedFormatKey":
                result[key] = transform(text)
            case let text as String where !Self.ruleKeys.contains(key):
                result[key] = transform(text, isBracketed: false)
            case let variable as [String: Any]:
                result[key] = transform(stringsdictVariable: variable)
            default:
                result[key] = value
            }
        }
    }

    /// The keys of a stringsdict that name rules rather than hold text.
    private static let ruleKeys: Set = ["NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"]

    /// A stringsdict variable's variants accented, nested ones too, with its rule keys as
    /// they are.
    private static func transform(stringsdictVariable variable: [String: Any]) -> [String: Any] {
        variable.reduce(into: [:]) { result, element in
            let (key, value) = element
            switch value {
            case let text as String where !ruleKeys.contains(key):
                result[key] = transform(text, isBracketed: false)
            case let nested as [String: Any]:
                result[key] = transform(stringsdictVariable: nested)
            default:
                result[key] = value
            }
        }
    }
}

extension Character {
    /// The letter with an accent or a stroke, as pseudo-localization draws it; any other
    /// character as it is.
    fileprivate var accented: Character {
        Self.accents[self] ?? self
    }

    /// Each ASCII letter's accented form: one that stays recognizable, so pseudo-localized
    /// text still reads.
    private static let accents: [Character: Character] = Dictionary(
        uniqueKeysWithValues: zip(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            "áƀçðéƒĝĥîĵķļɱñöþǫŕšţûṽŵẋýžÅƁÇÐÉƑĜĤÎĴĶĻṀÑÖÞǪŔŠŢÛṼŴẊÝŽ"
        )
    )
}
