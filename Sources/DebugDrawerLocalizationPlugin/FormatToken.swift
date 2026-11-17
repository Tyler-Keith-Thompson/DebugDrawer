#if DEBUG
    /// A run of a format string: literal text, or a format specifier that `String(format:)`
    /// replaces (`%@`, `%1$lld`, `%.2f`, `%%`) or a stringsdict variable (`%#@items@`).
    enum FormatToken: Equatable, Sendable {
        case literal(String)
        case specifier(String)
    }

    extension String {
        /// The string split into literal text and format specifiers, in order; joined, they are
        /// the string again. A `%` that starts no specifier is literal.
        ///
        /// A specifier is `%%`, a stringsdict variable `%#@name@`, or printf's form: an optional
        /// position (`1$`), flags (`-+ #0'`), a width (digits or `*`), a precision (`.` and
        /// digits or `*`), a length (`hh`, `h`, `ll`, `l`, `q`, `L`, `z`, `t`, `j`) and a
        /// conversion (`@dDiuUxXoOfFeEgGaAcCsSpn`).
        ///
        /// - Complexity: O(*n*), where *n* is the length of the string.
        var formatTokens: [FormatToken] {
            let characters = Array(self)
            var tokens: [FormatToken] = []
            var literal = ""
            var index = 0
            while index < characters.count {
                if characters[index] == "%", let end = characters.specifierEnd(from: index) {
                    if !literal.isEmpty {
                        tokens.append(.literal(literal))
                        literal = ""
                    }
                    tokens.append(.specifier(String(characters[index ..< end])))
                    index = end
                } else {
                    literal.append(characters[index])
                    index += 1
                }
            }
            if !literal.isEmpty {
                tokens.append(.literal(literal))
            }
            return tokens
        }
    }

    extension [Character] {
        /// The index just past the specifier that starts with the `%` at `start`, or `nil` when
        /// none does.
        fileprivate func specifierEnd(from start: Int) -> Int? {
            var index = start + 1
            guard index < count else { return nil }
            if self[index] == "%" {
                return index + 1
            }
            if self[index] == "#", index + 1 < count, self[index + 1] == "@",
               let close = self[(index + 2)...].firstIndex(of: "@"), close > index + 2 {
                // A stringsdict variable: `%#@name@`. Without a name and a closing `@`, `%#@` is
                // printf's `%@` with the `#` flag, as String(format:) reads it.
                return close + 1
            }
            // A position: digits and `$`.
            let digitsEnd = digitRun(from: index)
            if digitsEnd > index, digitsEnd < count, self[digitsEnd] == "$" {
                index = digitsEnd + 1
            }
            while index < count, "-+ #0'".contains(self[index]) {
                index += 1
            }
            index = widthEnd(from: index)
            if index < count, self[index] == "." {
                index = widthEnd(from: index + 1)
            }
            for length in ["hh", "ll", "h", "l", "q", "L", "z", "t", "j"] where hasRun(length, at: index) {
                index += length.count
                break
            }
            guard index < count, "@dDiuUxXoOfFeEgGaAcCsSpn".contains(self[index]) else { return nil }
            return index + 1
        }

        /// The index past the digits from `start`.
        private func digitRun(from start: Int) -> Int {
            var index = start
            while index < count, self[index].isASCII, self[index].isNumber {
                index += 1
            }
            return index
        }

        /// The index past a width or precision from `start`: digits, or `*` with an optional
        /// position (`*2$`).
        private func widthEnd(from start: Int) -> Int {
            guard start < count, self[start] == "*" else { return digitRun(from: start) }
            let digitsEnd = digitRun(from: start + 1)
            return digitsEnd > start + 1 && digitsEnd < count && self[digitsEnd] == "$" ? digitsEnd + 1 : start + 1
        }

        /// Whether `run` appears at `index`.
        private func hasRun(_ run: String, at index: Int) -> Bool {
            let run = Array(run)
            return index + run.count <= count && Array(self[index ..< index + run.count]) == run
        }
    }
#endif
