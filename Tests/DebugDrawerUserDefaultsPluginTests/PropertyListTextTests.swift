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
            #expect(PropertyListTextError.notNumber.message == "That isn't a number: use digits, a sign and a decimal point.")
            #expect(PropertyListTextError.data(.notBase64).message == DataTextError.notBase64.message)
        }

        @Test("A number's text reads as an integer when it is one and a real otherwise, around whitespace")
        func numbers() throws {
            let integer = try PropertyListType.number.value(parsing: " 42 ", encoding: .hex)
            let real = try PropertyListType.number.value(parsing: "-2.5", encoding: .hex)

            guard case let .number(integerNumber) = integer, case let .number(realNumber) = real else {
                Issue.record("Expected numbers, got \(integer) and \(real)")
                return
            }
            #expect(integerNumber == 42)
            #expect(String(cString: integerNumber.objCType) == "q")
            #expect(realNumber == -2.5)
            #expect(String(cString: realNumber.objCType) == "d")
        }

        @Test("Text that isn't a finite number is refused, empty text too")
        func notNumbers() {
            #expect(throws: PropertyListTextError.notNumber) { try PropertyListType.number.value(parsing: "", encoding: .hex) }
            #expect(throws: PropertyListTextError.notNumber) { try PropertyListType.number.value(parsing: "twelve", encoding: .hex) }
            #expect(throws: PropertyListTextError.notNumber) { try PropertyListType.number.value(parsing: "inf", encoding: .hex) }
            #expect(throws: PropertyListTextError.notNumber) { try PropertyListType.number.value(parsing: "nan", encoding: .hex) }
        }

        @Test("A string's text is the string as typed, and data's text is read in the encoding picked")
        func stringsAndData() throws {
            #expect(try PropertyListType.string.value(parsing: " spaced ", encoding: .hex) == .string(" spaced "))
            #expect(try PropertyListType.data.value(parsing: "ff00", encoding: .hex) == .data(Data([0xFF, 0x00])))
            #expect(try PropertyListType.data.value(parsing: "/wA=", encoding: .base64) == .data(Data([0xFF, 0x00])))
            #expect(throws: PropertyListTextError.data(.oddHexDigitCount)) { try PropertyListType.data.value(parsing: "f", encoding: .hex) }
        }

        @Test("Booleans, dates, arrays and dictionaries aren't read from text", arguments: [PropertyListType.boolean, .date, .array, .dictionary])
        func notText(type: PropertyListType) {
            #expect(throws: PropertyListTextError.notText) { try type.value(parsing: "true", encoding: .hex) }
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
