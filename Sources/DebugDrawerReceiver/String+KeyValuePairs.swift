// The one reading of `key=value` and `key: value` in free text, shared by the drawer's
// `DebugDrawerRedaction` (the Console's copies and report) and the diagnostics capture's
// `DebugDrawerDiagnosticsRedaction`, so a debug build's copy and a production capture mask the same
// pairs. It sits here because the receiver is the one module both reach: core imports it, and a
// production app links it without core.
//
// It walks the UTF-8 bytes once. Every byte it looks for (separators, quotes, delimiters) is ASCII,
// and in UTF-8 an ASCII byte is never part of another character, so a cut at one of them never
// splits a character. A regular expression was rejected: whether a key is sensitive is the caller's
// test (a key pattern found anywhere in the key), so an expression would only find the candidate
// keys and the code would test each anyway; the walk does both in one pass, with no copy of a text
// that has nothing to mask.

extension String {
    /// This text with the value of every `key=value` and `key: value` pair whose key `masksKey`
    /// accepts replaced with `mask`.
    ///
    /// - A key is a run of ASCII letters, digits, `_`, `-`, `.` and non-ASCII characters
    ///   (`user_token`, `x-api-key`, `auth.session`), or any text between double or single quotes
    ///   on one line (`"access token"`), as JSON writes keys.
    /// - The separator is `=` or `:`, with spaces or tabs on either side allowed. `==`, `::` and
    ///   `://` aren't separators, so comparisons, Swift's qualified names and URLs' schemes aren't
    ///   read as pairs.
    /// - A value in double or single quotes runs to the closing quote (a backslash escapes the next
    ///   character) and is masked inside them, the quotes kept (`"token": "[REDACTED]"`); one with no
    ///   closing quote on its line is masked to the line's end. Any other value runs up to the first
    ///   whitespace, `&`, `,`, `;`, `)`, `]`, `}` or quote, so a URL query string's items
    ///   (`?a=1&token=abc&b=2`) and comma-separated fields are masked one by one. An empty value, or
    ///   one starting with `{`, `[` or `(`, is left as it is; the pairs inside a bracket are read on
    ///   their own.
    /// - Every pair is read, a repeated key's included; a key `masksKey` refuses doesn't hide a
    ///   pair in its value (`note=token=abc` masks `abc`).
    ///
    /// - Parameters:
    ///   - mask: What a masked value becomes.
    ///   - masksKey: Whether a key's value is masked.
    /// - Returns: The text with the values masked; the text itself when nothing is.
    /// - Complexity: O(*n*) in the text's UTF-8 length, plus `masksKey` once per pair.
    package func maskingKeyValuePairs(with mask: String, where masksKey: (String) -> Bool) -> String {
        guard utf8.contains(where: { $0 == .equals || $0 == .colon }) else { return self }
        var text = self
        return text.withUTF8 { bytes in
            var scanner = KeyValueScanner(bytes: bytes, mask: Array(mask.utf8))
            return scanner.masked(where: masksKey) ?? self
        }
    }
}

/// One pass over a text's bytes, copying them to `output` only once a value is masked.
private struct KeyValueScanner {
    let bytes: UnsafeBufferPointer<UInt8>
    let mask: [UInt8]
    /// The text so far with its values masked; empty until the first is.
    private var output: [UInt8] = []
    /// Whether a value was masked.
    private var masksAny = false
    /// The bytes up to here are in `output`.
    private var copied = 0

    init(bytes: UnsafeBufferPointer<UInt8>, mask: [UInt8]) {
        self.bytes = bytes
        self.mask = mask
    }

    /// The text with the value of each pair whose key `masksKey` accepts masked, or `nil` when
    /// none was.
    mutating func masked(where masksKey: (String) -> Bool) -> String? {
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte.isQuote {
                // A quoted key is read only when a separator follows its closing quote; otherwise
                // the quote is a character like any other and its contents are read as text.
                // Each quote looks ahead only to the next quote of its kind on its line, so the
                // look-aheads add up to one more pass at most.
                if let close = closingQuote(of: byte, from: index + 1),
                   let valueStart = separatorEnd(from: close + 1),
                   masksKey(String(validUTF8: bytes[(index + 1) ..< close])) {
                    index = maskValue(from: valueStart)
                } else {
                    index += 1
                }
            } else if byte.isKeyByte {
                let start = index
                while index < bytes.count, bytes[index].isKeyByte {
                    index += 1
                }
                if let valueStart = separatorEnd(from: index),
                   masksKey(String(validUTF8: bytes[start ..< index])) {
                    index = maskValue(from: valueStart)
                }
            } else {
                index += 1
            }
        }
        guard masksAny else { return nil }
        output.append(contentsOf: bytes[copied...])
        return String(validUTF8: output)
    }

    /// Where a key's value starts: after the separator at `index` (spaces and tabs around it
    /// skipped); `nil` when no separator is there.
    private func separatorEnd(from index: Int) -> Int? {
        var index = skippingSpaces(from: index)
        guard index < bytes.count else { return nil }
        let separator = bytes[index]
        guard separator == .equals || separator == .colon else { return nil }
        index += 1
        if index < bytes.count {
            let next = bytes[index]
            if next == separator { return nil }
            if separator == .colon, next == .slash, index + 1 < bytes.count, bytes[index + 1] == .slash { return nil }
        }
        return skippingSpaces(from: index)
    }

    /// Masks the value starting at `start` and returns where reading goes on.
    private mutating func maskValue(from start: Int) -> Int {
        guard start < bytes.count else { return start }
        let first = bytes[start]
        if first.isQuote {
            if let close = closingQuote(of: first, from: start + 1) {
                replace(start + 1 ..< close)
                return close + 1
            }
            let end = lineEnd(from: start + 1)
            replace(start + 1 ..< end)
            return end
        }
        if first.opensBracket { return start }
        var end = start
        while end < bytes.count, !bytes[end].endsValue {
            end += 1
        }
        replace(start ..< end)
        return end
    }

    /// Replaces `range` with the mask; an empty range stays as it is.
    private mutating func replace(_ range: Range<Int>) {
        guard !range.isEmpty else { return }
        if !masksAny {
            masksAny = true
            output.reserveCapacity(bytes.count + mask.count)
        }
        output.append(contentsOf: bytes[copied ..< range.lowerBound])
        output.append(contentsOf: mask)
        copied = range.upperBound
    }

    /// The index of the quote closing one opened just before `index`, a backslash escaping the
    /// byte after it; `nil` when the line or the text ends first.
    private func closingQuote(of quote: UInt8, from index: Int) -> Int? {
        var index = index
        while index < bytes.count {
            switch bytes[index] {
            case quote: return index
            case .newline, .carriageReturn: return nil
            case .backslash: index += 2
            default: index += 1
            }
        }
        return nil
    }

    private func lineEnd(from index: Int) -> Int {
        var index = index
        while index < bytes.count, bytes[index] != .newline, bytes[index] != .carriageReturn {
            index += 1
        }
        return index
    }

    private func skippingSpaces(from index: Int) -> Int {
        var index = index
        while index < bytes.count, bytes[index] == .space || bytes[index] == .tab {
            index += 1
        }
        return index
    }
}

extension String {
    /// A string of `bytes`, which are valid UTF-8: cut from valid UTF-8 at ASCII bytes only, or
    /// joined from such cuts and the mask.
    fileprivate init(validUTF8 bytes: some Collection<UInt8>) {
        self.init(unsafeUninitializedCapacity: bytes.count) { buffer in
            buffer.initialize(fromContentsOf: bytes)
        }
    }
}

extension UInt8 {
    fileprivate static let equals = UInt8(ascii: "=")
    fileprivate static let colon = UInt8(ascii: ":")
    fileprivate static let slash = UInt8(ascii: "/")
    fileprivate static let backslash = UInt8(ascii: "\\")
    fileprivate static let space = UInt8(ascii: " ")
    fileprivate static let tab = UInt8(ascii: "\t")
    fileprivate static let newline = UInt8(ascii: "\n")
    fileprivate static let carriageReturn = UInt8(ascii: "\r")

    /// A letter, digit, `_`, `-`, `.`, or a byte of a non-ASCII character.
    fileprivate var isKeyByte: Bool {
        switch self {
        case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "0") ... UInt8(ascii: "9"),
             UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: "."), 0x80...: true
        default: false
        }
    }

    fileprivate var isQuote: Bool {
        self == UInt8(ascii: "\"") || self == UInt8(ascii: "'")
    }

    fileprivate var opensBracket: Bool {
        self == UInt8(ascii: "{") || self == UInt8(ascii: "[") || self == UInt8(ascii: "(")
    }

    /// Whether an unquoted value ends before this byte.
    fileprivate var endsValue: Bool {
        switch self {
        case .space, .tab, .newline, .carriageReturn, UInt8(ascii: "&"), UInt8(ascii: ","), UInt8(ascii: ";"),
             UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"), UInt8(ascii: "\""), UInt8(ascii: "'"): true
        default: false
        }
    }
}
