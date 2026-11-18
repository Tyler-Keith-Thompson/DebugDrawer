#if DEBUG
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import Testing

    @Suite
    struct PropertyListTextTests {
        @Test("Hex shows two lowercase digits a byte with a space after every fourth byte")
        func hexText() {
            let data = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x0A])
            let expected = "deadbeef 010a"

            let actual = DataTextEncoding.hex.text(for: data)

            #expect(actual == expected)
            #expect(DataTextEncoding.hex.text(for: Data()) == "")
            #expect(DataTextEncoding.hex.text(for: Data([0xFF])) == "ff")
            #expect(DataTextEncoding.hex.text(for: Data([1, 2, 3, 4])) == "01020304")
        }

        @Test("Hex reads either case and ignores whitespace between digits")
        func hexReads() throws {
            let expected = Data([0xDE, 0xAD, 0xBE, 0xEF])

            let actual = try DataTextEncoding.hex.data(from: " DEad\nbe ef ")

            #expect(actual == expected)
            #expect(try DataTextEncoding.hex.data(from: "") == Data())
        }

        @Test("Hex refuses a character that isn't a digit, a fullwidth digit too, and an odd count of digits")
        func hexErrors() {
            #expect(throws: DataTextError.notHexDigit("g")) { try DataTextEncoding.hex.data(from: "0g") }
            #expect(throws: DataTextError.notHexDigit("１")) { try DataTextEncoding.hex.data(from: "１２") }
            #expect(throws: DataTextError.oddHexDigitCount) { try DataTextEncoding.hex.data(from: "abc") }
        }

        @Test("Base64 round-trips bytes and refuses text that isn't Base64")
        func base64() throws {
            let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
            let expected = "3q2+7w=="

            let actual = DataTextEncoding.base64.text(for: data)

            #expect(actual == expected)
            #expect(try DataTextEncoding.base64.data(from: "3q2+\n7w==") == data)
            #expect(throws: DataTextError.notBase64) { try DataTextEncoding.base64.data(from: "not base64!") }
        }

        @Test("Each problem says what's wrong in a sentence")
        func messages() {
            #expect(DataTextError.notHexDigit("g").message == "“g” isn't a hex digit (0–9, a–f).")
            #expect(DataTextError.oddHexDigitCount.message == "Hex needs two digits a byte; there's one left over.")
            #expect(DataTextError.notBase64.message == "That isn't Base64: use A–Z, a–z, 0–9, + and /, padded with =.")
            #expect(PropertyListTextError.notInteger.message == "That isn't a whole number: the value is an integer, so use digits and a sign.")
            #expect(PropertyListTextError.notNumber.message == "That isn't a number: use digits, a sign and a decimal point.")
            #expect(PropertyListTextError.data(.notBase64).message == DataTextError.notBase64.message)
        }

        @Test("An integer's text reads as an integer, around whitespace, and past Int.max as an unsigned one")
        func integers() throws {
            let integer = PropertyListValue.number(NSNumber(value: 3))

            let actual = try integer.replacement(parsing: " 42 ", encoding: .hex)
            let negative = try integer.replacement(parsing: "-7", encoding: .hex)
            let unsigned = try integer.replacement(parsing: "18446744073709551615", encoding: .hex)

            guard case let .number(actualNumber) = actual, case let .number(negativeNumber) = negative,
                  case let .number(unsignedNumber) = unsigned else {
                Issue.record("Expected numbers, got \(actual), \(negative) and \(unsigned)")
                return
            }
            #expect(actualNumber == 42)
            #expect(String(cString: actualNumber.objCType) == "q")
            #expect(negativeNumber == -7)
            #expect(unsignedNumber.uint64Value == UInt64.max)
            #expect(!CFNumberIsFloatType(unsignedNumber as CFNumber))
        }

        @Test("A real's text reads as a real, a whole number too")
        func reals() throws {
            let real = PropertyListValue.number(NSNumber(value: 2.5))

            let whole = try real.replacement(parsing: "3", encoding: .hex)
            let fraction = try real.replacement(parsing: " -2.25 ", encoding: .hex)

            guard case let .number(wholeNumber) = whole, case let .number(fractionNumber) = fraction else {
                Issue.record("Expected numbers, got \(whole) and \(fraction)")
                return
            }
            #expect(wholeNumber == 3)
            #expect(String(cString: wholeNumber.objCType) == "d")
            #expect(fractionNumber == -2.25)
            #expect(String(cString: fractionNumber.objCType) == "d")
        }

        @Test("Text that isn't a whole number, a real or empty text among it, is refused for an integer")
        func notIntegers() {
            let integer = PropertyListValue.number(NSNumber(value: 3))

            #expect(throws: PropertyListTextError.notInteger) { try integer.replacement(parsing: "", encoding: .hex) }
            #expect(throws: PropertyListTextError.notInteger) { try integer.replacement(parsing: "3.5", encoding: .hex) }
            #expect(throws: PropertyListTextError.notInteger) { try integer.replacement(parsing: "twelve", encoding: .hex) }
            #expect(throws: PropertyListTextError.notInteger) { try integer.replacement(parsing: "18446744073709551616", encoding: .hex) }
        }

        @Test("Text that isn't a finite number is refused for a real, empty text too")
        func notNumbers() {
            let real = PropertyListValue.number(NSNumber(value: 2.5))

            #expect(throws: PropertyListTextError.notNumber) { try real.replacement(parsing: "", encoding: .hex) }
            #expect(throws: PropertyListTextError.notNumber) { try real.replacement(parsing: "twelve", encoding: .hex) }
            #expect(throws: PropertyListTextError.notNumber) { try real.replacement(parsing: "inf", encoding: .hex) }
            #expect(throws: PropertyListTextError.notNumber) { try real.replacement(parsing: "nan", encoding: .hex) }
        }

        @Test("A string's text is the string as typed, and data's text is read in the encoding picked")
        func stringsAndData() throws {
            let string = PropertyListValue.string("")
            let data = PropertyListValue.data(Data())

            #expect(try string.replacement(parsing: " spaced ", encoding: .hex) == .string(" spaced "))
            #expect(try data.replacement(parsing: "ff00", encoding: .hex) == .data(Data([0xFF, 0x00])))
            #expect(try data.replacement(parsing: "/wA=", encoding: .base64) == .data(Data([0xFF, 0x00])))
            #expect(throws: PropertyListTextError.data(.oddHexDigitCount)) { try data.replacement(parsing: "f", encoding: .hex) }
        }

        @Test("Booleans, dates, arrays and dictionaries aren't read from text", arguments: [PropertyListType.boolean, .date, .array, .dictionary])
        func notText(type: PropertyListType) {
            let value = type.initialValue(now: .distantPast)

            #expect(throws: PropertyListTextError.notText) { try value.replacement(parsing: "true", encoding: .hex) }
        }

        @Test("A key added with each type starts empty, zero, false or now")
        func initialValues() {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let expected: [PropertyListValue] = [.string(""), .number(0), .bool(false), .date(now), .data(Data()), .array([]), .dictionary([:])]

            let actual = PropertyListType.allCases.map { $0.initialValue(now: now) }

            #expect(actual == expected)
            #expect(PropertyListType.allCases.map(\.title) == ["String", "Number", "Boolean", "Date", "Data", "Array", "Dictionary"])
        }
    }
#endif
