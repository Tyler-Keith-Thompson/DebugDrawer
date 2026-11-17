#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct NetworkMocksModelTests {
        @Test("The first enabled rule that matches answers, in the list's order; a disabled one is skipped")
        func firstEnabledMatchWins() throws {
            let active = NetworkMockRules()
            let sut = NetworkMocksModel(storage: FakeNetworkMockStorage(), active: active)
            let disabled = NetworkMockRule(name: "Off", isEnabled: false, matcher: .init(host: .exact("api.test")), response: .init(status: 500))
            let specific = NetworkMockRule(
                name: "Specific", matcher: .init(host: .exact("api.test"), path: .exact("/users/1")), response: .init(status: 201)
            )
            let general = NetworkMockRule(name: "General", matcher: .init(host: .exact("api.test")), response: .init(status: 202))
            let specificURL = try #require(URL(string: "https://api.test/users/1"))
            let otherURL = try #require(URL(string: "https://api.test/orders"))
            sut.save(disabled)
            sut.save(specific)
            sut.save(general)

            let actualSpecific = active.answer(method: "GET", url: specificURL)?.ruleName
            let actualOther = active.answer(method: "GET", url: otherURL)?.ruleName

            #expect(actualSpecific == "Specific")
            #expect(actualOther == "General")
        }

        @Test("Moving a rule earlier makes it answer first; a move past either end stops there")
        func reorder() throws {
            let active = NetworkMockRules()
            let sut = NetworkMocksModel(storage: FakeNetworkMockStorage(), active: active)
            let first = NetworkMockRule(name: "First", matcher: .init(), response: .init(status: 201))
            let second = NetworkMockRule(name: "Second", matcher: .init(), response: .init(status: 202))
            let third = NetworkMockRule(name: "Third", matcher: .init(), response: .init(status: 203))
            let url = try #require(URL(string: "https://api.test/"))
            for rule in [first, second, third] {
                sut.save(rule)
            }

            sut.move(third.id, by: -1)
            let afterOne = sut.rules.map(\.name)
            sut.move(third.id, by: -5)
            let afterTop = sut.rules.map(\.name)
            sut.move(first.id, by: 9)
            let afterBottom = sut.rules.map(\.name)
            let actualAnswer = active.answer(method: "GET", url: url)?.ruleName

            #expect(afterOne == ["First", "Third", "Second"])
            #expect(afterTop == ["Third", "First", "Second"])
            #expect(afterBottom == ["Third", "Second", "First"])
            #expect(actualAnswer == "Third")
        }

        @Test("Each change is saved: a new model over the same storage loads the rules, order and switches")
        func persistsAcrossLaunches() throws {
            let storage = FakeNetworkMockStorage()
            let first = NetworkMockRule(name: "First", matcher: .init(host: .exact("a.test")), response: .init(status: 200))
            let second = NetworkMockRule(name: "Second", matcher: .init(host: .exact("b.test")), response: .init(status: 404))
            let launch = NetworkMocksModel(storage: storage, active: NetworkMockRules())
            launch.save(first)
            launch.save(second)
            launch.move(second.id, by: -1)
            launch.setEnabled(false, id: first.id)
            let relaunchActive = NetworkMockRules()
            let relaunch = NetworkMocksModel(storage: storage, active: relaunchActive)
            let url = try #require(URL(string: "https://b.test/"))

            relaunch.load()

            #expect(relaunch.rules.map(\.name) == ["Second", "First"])
            #expect(relaunch.rules.map(\.isEnabled) == [true, false])
            #expect(relaunchActive.answer(method: "GET", url: url)?.status == 404)
            #expect(relaunch.issue == nil)
        }

        @Test("Rules installed with the app are added once, after the saved ones; a saved rule of the same id wins")
        func loadAdding() throws {
            let storage = FakeNetworkMockStorage()
            let seeded = NetworkMockRule(name: "Seeded", matcher: .init(), response: .init(status: 200))
            let firstLaunch = NetworkMocksModel(storage: storage, active: NetworkMockRules())
            firstLaunch.load(adding: [seeded])
            var edited = seeded
            edited.response.status = 418
            firstLaunch.save(edited)
            let secondLaunch = NetworkMocksModel(storage: storage, active: NetworkMockRules())

            secondLaunch.load(adding: [seeded])

            #expect(secondLaunch.rules.count == 1)
            #expect(secondLaunch.rules.first?.response.status == 418)
        }

        @Test("A saved file of a later format loads no rules and says why")
        func laterFormat() {
            let storage = FakeNetworkMockStorage(rules: Data(#"{"version": 9, "rules": []}"#.utf8))
            let sut = NetworkMocksModel(storage: storage, active: NetworkMockRules())

            sut.load()

            #expect(sut.rules.isEmpty)
            #expect(sut.issue == .unsupportedVersion(9))
        }

        @Test("A change that can't be saved still applies, and says it wasn't saved")
        func notSaved() throws {
            let storage = FakeNetworkMockStorage()
            storage.failsWriting = true
            let active = NetworkMockRules()
            let sut = NetworkMocksModel(storage: storage, active: active)
            let rule = NetworkMockRule(name: "Unsaved", matcher: .init(), response: .init(status: 200))
            let url = try #require(URL(string: "https://api.test/"))

            sut.save(rule)

            #expect(sut.issue == .notSaved)
            #expect(active.answer(method: "GET", url: url)?.ruleName == "Unsaved")
        }

        @Test("Editing a rule replaces it in place; deleting it removes its body file unless another rule names it")
        func editAndDelete() {
            let storage = FakeNetworkMockStorage(bodies: ["kept.json": Data("{}".utf8), "only.json": Data("[]".utf8)])
            let sut = NetworkMocksModel(storage: storage, active: NetworkMockRules())
            let shared = NetworkMockRule(name: "A", matcher: .init(), response: .init(body: .file("kept.json")))
            let alsoShared = NetworkMockRule(name: "B", matcher: .init(), response: .init(body: .file("kept.json")))
            let alone = NetworkMockRule(name: "C", matcher: .init(), response: .init(body: .file("only.json")))
            for rule in [shared, alsoShared, alone] {
                sut.save(rule)
            }
            var renamed = alsoShared
            renamed.name = "B2"

            sut.save(renamed)
            sut.delete(shared.id)
            sut.delete(alone.id)

            #expect(sut.rules.map(\.name) == ["B2"])
            #expect(storage.bodies.keys.sorted() == ["kept.json"])
        }

        @Test("A rule whose pattern doesn't compile never answers; the others still do")
        func invalidPatternSkipped() throws {
            let active = NetworkMockRules()
            let sut = NetworkMocksModel(storage: FakeNetworkMockStorage(), active: active)
            let broken = NetworkMockRule(name: "Broken", matcher: .init(path: .regex("(")), response: .init(status: 500))
            let fine = NetworkMockRule(name: "Fine", matcher: .init(), response: .init(status: 200))
            let url = try #require(URL(string: "https://api.test/("))
            sut.save(broken)
            sut.save(fine)

            let actual = active.answer(method: "GET", url: url)?.ruleName

            #expect(actual == "Fine")
            #expect(broken.hasInvalidPattern)
            #expect(sut.enabledCount == 2)
        }

        @Test("A body file's bytes are sent, typed by its extension; a missing file sends an empty body")
        func fileBody() throws {
            let active = NetworkMockRules()
            let storage = FakeNetworkMockStorage(bodies: ["avatar.png": Data([0x89, 0x50, 0x4E, 0x47])])
            let sut = NetworkMocksModel(storage: storage, active: active)
            sut.save(NetworkMockRule(name: "Avatar", matcher: .init(path: .exact("/avatar")), response: .init(body: .file("avatar.png"))))
            sut.save(NetworkMockRule(name: "Gone", matcher: .init(path: .exact("/gone")), response: .init(body: .file("gone.json"))))
            let avatar = try #require(URL(string: "https://api.test/avatar"))
            let gone = try #require(URL(string: "https://api.test/gone"))

            let actualAvatar = try #require(active.answer(method: "GET", url: avatar))
            let actualGone = try #require(active.answer(method: "GET", url: gone))

            #expect(actualAvatar.body == Data([0x89, 0x50, 0x4E, 0x47]))
            #expect(actualAvatar.headers == ["Content-Type": "image/png", "Content-Length": "4"])
            #expect(actualGone.body.isEmpty)
            #expect(actualGone.headers["Content-Length"] == "0")
        }

        @Test("Content-Length is the body's length and the content type replaces the headers' own, in any case")
        func headerFields() {
            let response = NetworkMockRule.Response(
                status: 200, headers: ["content-type": "text/plain", "content-length": "999", "X-Mock": "1"], contentType: "application/json"
            )
            let expected = ["Content-Type": "application/json", "Content-Length": "12", "X-Mock": "1"]

            let actual = response.headerFields(bodyLength: 12)

            #expect(actual == expected)
        }

        @Test("Without a content type the headers' own is kept, even over a file's type")
        func headersOwnContentType() {
            let response = NetworkMockRule.Response(headers: ["Content-Type": "text/csv"])
            let expected = ["Content-Type": "text/csv", "Content-Length": "0"]

            let actual = response.headerFields(bodyLength: 0, fileType: "image/png")

            #expect(actual == expected)
        }

        @Test("An empty registry answers nothing")
        func emptyRegistry() throws {
            let sut = NetworkMockRules()
            let url = try #require(URL(string: "https://api.test/"))

            let actual = sut.answer(method: "GET", url: url)

            #expect(actual == nil)
        }
    }
#endif
