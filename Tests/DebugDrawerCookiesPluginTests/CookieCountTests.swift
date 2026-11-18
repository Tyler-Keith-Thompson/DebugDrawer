#if DEBUG
    @testable import DebugDrawerCookiesPlugin
    import Testing

    @Suite
    struct CookieCountTests {
        @Test("With nothing filtered out the count names every cookie, and Delete All asks about all of them")
        func unfiltered() {
            let sut = CookieCount(shown: 12, total: 12)
            let expectedLabel = "12 cookies"
            let expectedQuestion = "Delete all 12 cookies?"
            let expectedExplanation = "Each is deleted from the store it is in."

            #expect(sut.label == expectedLabel)
            #expect(sut.deleteQuestion == expectedQuestion)
            #expect(sut.deleteExplanation == expectedExplanation)
            #expect(!sut.isFiltered)
        }

        @Test("While the filter hides some the count says how many of all, and Delete All asks about the ones shown")
        func filtered() {
            let sut = CookieCount(shown: 3, total: 12)
            let expectedLabel = "3 of 12 cookies"
            let expectedQuestion = "Delete the 3 cookies the filter shows?"
            let expectedExplanation = "Each is deleted from the store it is in. The 9 the filter hides stay."

            #expect(sut.label == expectedLabel)
            #expect(sut.deleteQuestion == expectedQuestion)
            #expect(sut.deleteExplanation == expectedExplanation)
            #expect(sut.isFiltered)
        }

        @Test("One cookie is named in the singular, shown or hidden")
        func singular() {
            let only = CookieCount(shown: 1, total: 1)
            let oneShown = CookieCount(shown: 1, total: 2)

            #expect(only.label == "1 cookie")
            #expect(only.deleteQuestion == "Delete the only cookie?")
            #expect(oneShown.label == "1 of 2 cookies")
            #expect(oneShown.deleteQuestion == "Delete the cookie the filter shows?")
            #expect(oneShown.deleteExplanation == "Each is deleted from the store it is in. The one the filter hides stays.")
        }

        @Test("No cookies at all is 0 cookies, and a filter that matches none is 0 of all")
        func empty() {
            let none = CookieCount(shown: 0, total: 0)
            let noMatches = CookieCount(shown: 0, total: 4)

            #expect(none.label == "0 cookies")
            #expect(noMatches.label == "0 of 4 cookies")
        }
    }
#endif
