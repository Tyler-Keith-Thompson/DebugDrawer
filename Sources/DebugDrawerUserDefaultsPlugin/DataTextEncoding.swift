#if DEBUG
    import Foundation

    /// How the editor writes bytes as text: hexadecimal digits, or Base64.
    enum DataTextEncoding: String, CaseIterable, Identifiable {
        case hex = "Hex"
        case base64 = "Base64"

        var id: Self {
            self
        }

        /// The encoding's name.
        var title: String {
            rawValue
        }

        /// `data` as text: in hex, two lowercase digits a byte with a space after every fourth
        /// byte, as Xcode shows data; in Base64, padded, on one line.
        func text(for data: Data) -> String {
            switch self {
            case .hex:
                data.enumerated().map { offset, byte in
                    (offset > 0 && offset.isMultiple(of: 4) ? " " : "") + String(format: "%02x", byte)
                }
                .joined()
            case .base64:
                data.base64EncodedString()
            }
        }

        /// The bytes `text` holds. Whitespace between digits is ignored, in either encoding.
        ///
        /// - Throws: ``DataTextError`` saying why the text isn't bytes in the encoding.
        func data(from text: String) throws(DataTextError) -> Data {
            let digits = text.filter { !$0.isWhitespace }
            switch self {
            case .hex:
                // ASCII only: `isHexDigit` also accepts the fullwidth digits, which don't parse.
                if let invalid = digits.first(where: { !($0.isASCII && $0.isHexDigit) }) {
                    throw .notHexDigit(invalid)
                }
                guard digits.count.isMultiple(of: 2) else { throw .oddHexDigitCount }
                var bytes = [UInt8]()
                bytes.reserveCapacity(digits.count / 2)
                var index = digits.startIndex
                while index < digits.endIndex {
                    let next = digits.index(index, offsetBy: 2)
                    // Two characters, each an ASCII hex digit (checked above), always parse.
                    bytes.append(UInt8(digits[index ..< next], radix: 16) ?? 0)
                    index = next
                }
                return Data(bytes)
            case .base64:
                guard let data = Data(base64Encoded: digits) else { throw .notBase64 }
                return data
            }
        }
    }

    /// Why text isn't bytes in a ``DataTextEncoding``.
    enum DataTextError: Error, Equatable {
        /// A character that isn't 0–9 or a–f.
        case notHexDigit(Character)
        /// An odd count of hex digits, which leaves half a byte.
        case oddHexDigitCount
        /// Text that isn't padded Base64.
        case notBase64

        /// The problem as the editor shows it under the field.
        var message: String {
            switch self {
            case let .notHexDigit(character): "“\(character)” isn't a hex digit (0–9, a–f)."
            case .oddHexDigitCount: "Hex needs two digits a byte; there's one left over."
            case .notBase64: "That isn't Base64: use A–Z, a–z, 0–9, + and /, padded with =."
            }
        }
    }
#endif
