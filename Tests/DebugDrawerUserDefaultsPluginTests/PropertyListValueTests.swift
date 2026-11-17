#if DEBUG
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import Testing

    @Suite
    struct PropertyListValueTests {
        @Test("Each property-list object reads as its kind, a Boolean apart from a number, nested values too")
        func readsEachKind() {
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let object: [String: Any] = [
                "string": "ada", "integer": 3, "real": 2.5, "bool": true, "date": date,
                "data": Data([1, 2]), "array": [1, "two"], "dictionary": ["nested": ["deep": false]]
            ]
            let expected = PropertyListValue.dictionary([
                "string": .string("ada"), "integer": .number(3), "real": .number(2.5), "bool": .bool(true),
                "date": .date(date), "data": .data(Data([1, 2])), "array": .array([.number(1), .string("two")]),
                "dictionary": .dictionary(["nested": .dictionary(["deep": .bool(false)])])
            ])

            let actual = PropertyListValue(propertyList: object)

            #expect(actual == expected)
        }

        @Test("An object no property list holds, at any depth, reads as nothing")
        func rejectsNonPropertyList() {
            #expect(PropertyListValue(propertyList: NSObject()) == nil)
            #expect(PropertyListValue(propertyList: [NSObject()]) == nil)
            #expect(PropertyListValue(propertyList: ["key": [NSObject()]]) == nil)
        }

        @Test("A value written back keeps an integer an integer, a real a real and a Boolean a Boolean")
        func roundTripKeepsNumberKinds() throws {
            let value = PropertyListValue.array([.number(3), .number(2.5), .bool(false)])

            let actual = try #require(value.propertyList as? [NSNumber])

            #expect(actual.count == 3)
            #expect(String(cString: actual[0].objCType) == "q")
            #expect(String(cString: actual[1].objCType) == "d")
            #expect(CFGetTypeID(actual[2]) == CFBooleanGetTypeID())
            #expect(PropertyListValue(propertyList: value.propertyList) == value)
        }

        @Test("A summary is one line: the string, the number, true or false, an ISO 8601 date, or a count")
        func summaries() {
            let date = Date(timeIntervalSince1970: 1_800_000_000)

            #expect(PropertyListValue.string("ada").summary == "ada")
            #expect(PropertyListValue.number(2.5).summary == "2.5")
            #expect(PropertyListValue.bool(true).summary == "true")
            #expect(PropertyListValue.date(date).summary == "2027-01-15T08:00:00Z")
            #expect(PropertyListValue.data(Data([1])).summary == "1 byte")
            #expect(PropertyListValue.data(Data()).summary == "0 bytes")
            #expect(PropertyListValue.array([.number(1), .number(2)]).summary == "2 items")
            #expect(PropertyListValue.array([.number(1)]).summary == "1 item")
            #expect(PropertyListValue.dictionary([:]).summary == "0 keys")
            #expect(PropertyListValue.dictionary(["a": .bool(true)]).summary == "1 key")
        }

        @Test("An array's children are its elements by index, and a dictionary's its values by sorted key")
        func children() {
            let array = PropertyListValue.array([.string("a"), .string("b")])
            let dictionary = PropertyListValue.dictionary(["b": .number(2), "a": .number(1)])
            let expectedArray = [
                PropertyListChild(component: .index(0), value: .string("a")),
                PropertyListChild(component: .index(1), value: .string("b"))
            ]
            let expectedDictionary = [
                PropertyListChild(component: .key("a"), value: .number(1)),
                PropertyListChild(component: .key("b"), value: .number(2))
            ]

            #expect(array.children == expectedArray)
            #expect(dictionary.children == expectedDictionary)
            #expect(PropertyListValue.string("leaf").children.isEmpty)
        }

        @Test("A path leads to a nested value; an empty path to the value itself; a wrong step to nothing")
        func valueAtPath() {
            let value = PropertyListValue.dictionary(["tabs": .array([.string("recent"), .dictionary(["pinned": .bool(true)])])])

            #expect(value.value(at: []) == value)
            #expect(value.value(at: [.key("tabs"), .index(1), .key("pinned")]) == .bool(true))
            #expect(value.value(at: [.key("tabs"), .index(2)]) == nil)
            #expect(value.value(at: [.key("tabs"), .index(-1)]) == nil)
            #expect(value.value(at: [.index(0)]) == nil)
            #expect(value.value(at: [.key("tabs"), .index(0), .key("deeper")]) == nil)
        }

        @Test("Replacing deep inside rebuilds every container above it and leaves the rest as it was")
        func replaceNested() {
            let value = PropertyListValue.dictionary([
                "tabs": .array([.string("recent"), .dictionary(["pinned": .bool(true), "title": .string("Home")])]),
                "sync": .bool(true)
            ])
            let expected = PropertyListValue.dictionary([
                "tabs": .array([.string("recent"), .dictionary(["pinned": .bool(false), "title": .string("Home")])]),
                "sync": .bool(true)
            ])

            let actual = value.replacing(at: [.key("tabs"), .index(1), .key("pinned")], with: .bool(false))

            #expect(actual == expected)
        }

        @Test("Removing an array's element shifts the rest down; removing a dictionary's key drops it")
        func removeNested() {
            let array = PropertyListValue.array([.number(1), .number(2), .number(3)])
            let dictionary = PropertyListValue.dictionary(["a": .number(1), "b": .number(2)])

            #expect(array.replacing(at: [.index(0)], with: nil) == .array([.number(2), .number(3)]))
            #expect(dictionary.replacing(at: [.key("a")], with: nil) == .dictionary(["b": .number(2)]))
        }

        @Test("An empty path replaces the whole value; removing at it, or replacing on a path that leads nowhere, changes nothing")
        func replaceEdges() {
            let value = PropertyListValue.array([.number(1)])

            #expect(value.replacing(at: [], with: .string("new")) == .string("new"))
            #expect(value.replacing(at: [], with: nil) == value)
            #expect(value.replacing(at: [.index(5)], with: .string("new")) == value)
            #expect(value.replacing(at: [.key("a")], with: .string("new")) == value)
        }

        @Test("Adding appends to an array, sets a dictionary's key, and is refused by a value that holds none")
        func adding() {
            let array = PropertyListValue.array([.number(1)])
            let dictionary = PropertyListValue.dictionary(["a": .number(1)])
            let expectedArray = PropertyListAddition(container: .array([.number(1), .string("")]), component: .index(1))
            let expectedDictionary = PropertyListAddition(container: .dictionary(["a": .number(1), "b": .bool(false)]), component: .key("b"))

            #expect(array.adding(.string(""), forKey: "ignored") == expectedArray)
            #expect(dictionary.adding(.bool(false), forKey: "b") == expectedDictionary)
            #expect(PropertyListValue.string("leaf").adding(.number(1), forKey: "a") == nil)
        }

        @Test("A path's steps read as an index in brackets or the key")
        func pathTitles() {
            #expect(PropertyListPathComponent.index(2).title == "[2]")
            #expect(PropertyListPathComponent.key("theme").title == "theme")
        }

        @Test("Copied text is data in hex and a container in Foundation's description")
        func copiedText() {
            #expect(PropertyListValue.data(Data([0xDE, 0xAD])).copiedText == "dead")
            #expect(PropertyListValue.array([.number(1), .string("a")]).copiedText == "(\n    1,\n    a\n)")
            #expect(PropertyListValue.string("ada").copiedText == "ada")
        }
    }
#endif
