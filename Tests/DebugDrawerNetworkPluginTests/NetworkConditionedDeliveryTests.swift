#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os
    import Testing

    // Each test times a delivery on a scheduler it advances by hand, and records what the delivery
    // hands on as one line per event: "response 200", "data 100", "finished", "failed -1001".
    @Suite
    struct NetworkConditionedDeliveryTests {
        @Test("Nothing happens before the latency; at the latency the request proceeds")
        func latency() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Slow", latency: .milliseconds(2000), bandwidth: nil, failure: nil)
            let proceeded = OSAllocatedUnfairLock(initialState: 0)
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { _ in }
            let url = try #require(URL(string: "https://api.example.com/"))

            sut.start(url: url) { proceeded.withLock { $0 += 1 } }
            scheduler.advance(by: .milliseconds(1999))
            let beforeLatency = proceeded.withLock { $0 }
            scheduler.advance(by: .milliseconds(1))
            let atLatency = proceeded.withLock { $0 }

            #expect(scheduler.snapshot.delays == [.milliseconds(2000)])
            #expect(beforeLatency == 0)
            #expect(atLatency == 1)
        }

        @Test("With no latency the request proceeds at once, and nothing is scheduled")
        func noLatency() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Capped", latency: .zero, bandwidth: 1000, failure: nil)
            let proceeded = OSAllocatedUnfairLock(initialState: 0)
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { _ in }
            let url = try #require(URL(string: "https://api.example.com/"))

            sut.start(url: url) { proceeded.withLock { $0 += 1 } }

            #expect(proceeded.withLock { $0 } == 1)
            #expect(scheduler.snapshot.delays.isEmpty)
        }

        @Test(
            "A failing profile fails the request after the latency, with its error, and the request never proceeds",
            arguments: [
                (NetworkConditionProfile.Failure.timedOut, ["failed \(NSURLErrorTimedOut)"]),
                (.notConnectedToInternet, ["failed \(NSURLErrorNotConnectedToInternet)"]),
                (.internalServerError, ["response 500", "finished"])
            ]
        )
        func failure(failure: NetworkConditionProfile.Failure, expected: [String]) throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Down", latency: .milliseconds(300), bandwidth: nil, failure: failure)
            let events = OSAllocatedUnfairLock(initialState: [String]())
            let proceeded = OSAllocatedUnfairLock(initialState: 0)
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { event in
                events.withLock { $0.append(event.line) }
            }
            let url = try #require(URL(string: "https://api.example.com/"))

            sut.start(url: url) { proceeded.withLock { $0 += 1 } }
            scheduler.advance(by: .milliseconds(299))
            let beforeLatency = events.withLock { $0 }
            scheduler.advance(by: .milliseconds(1))
            let actual = events.withLock { $0 }

            #expect(beforeLatency.isEmpty)
            #expect(actual == expected)
            #expect(proceeded.withLock { $0 } == 0)
        }

        @Test("The 500 a failing profile synthesizes carries the request's URL and an empty body")
        func serverErrorResponse() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Down", latency: .zero, bandwidth: nil, failure: .internalServerError)
            let responses = OSAllocatedUnfairLock(initialState: [HTTPURLResponse]())
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { event in
                if case let .response(response) = event, let http = response as? HTTPURLResponse {
                    responses.withLock { $0.append(http) }
                }
            }
            let url = try #require(URL(string: "https://api.example.com/v1/orders"))

            sut.start(url: url) {}

            let actual = try #require(responses.withLock { $0 }.first)
            #expect(actual.statusCode == 500)
            #expect(actual.url == url)
            #expect(actual.value(forHTTPHeaderField: "Content-Length") == "0")
        }

        @Test("A capped body arrives a tenth of a second's worth at a time: 250 bytes at 1,000 B/s in parts at 100, 200 and 250 ms")
        func bandwidthChunks() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Capped", latency: .zero, bandwidth: 1000, failure: nil)
            let events = OSAllocatedUnfairLock(initialState: [String]())
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { event in
                events.withLock { $0.append(event.line) }
            }
            let url = try #require(URL(string: "https://api.example.com/"))
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
            let body = Data(repeating: 7, count: 250)

            sut.deliver(response, body: body)
            let atStart = events.withLock { $0 }
            scheduler.advance(by: .milliseconds(99))
            let at99 = events.withLock { $0 }
            scheduler.advance(by: .milliseconds(1))
            let at100 = events.withLock { $0 }
            scheduler.advance(by: .milliseconds(100))
            let at200 = events.withLock { $0 }
            scheduler.advance(by: .milliseconds(49))
            let at249 = events.withLock { $0 }
            scheduler.advance(by: .milliseconds(1))
            let at250 = events.withLock { $0 }

            #expect(atStart == ["response 200"])
            #expect(at99 == ["response 200"])
            #expect(at100 == ["response 200", "data 100"])
            #expect(at200 == ["response 200", "data 100", "data 100"])
            #expect(at249 == at200)
            #expect(at250 == ["response 200", "data 100", "data 100", "data 50", "finished"])
            #expect(scheduler.snapshot.delays == [.milliseconds(100), .milliseconds(100), .milliseconds(50)])
        }

        @Test("The parts of a capped body join into the body as sent")
        func bandwidthKeepsBody() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Capped", latency: .zero, bandwidth: 30, failure: nil)
            let received = OSAllocatedUnfairLock(initialState: Data())
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { event in
                if case let .data(data) = event { received.withLock { $0.append(data) } }
            }
            let url = try #require(URL(string: "https://api.example.com/"))
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
            let expected = Data((0 ..< 100).map { UInt8($0) })

            sut.deliver(response, body: expected)
            scheduler.advance(by: .seconds(4))

            #expect(received.withLock { $0 } == expected)
            #expect(scheduler.snapshot.delays.count == 34)
        }

        @Test("With no cap the response, the whole body and the finish come at once; an empty capped body finishes at once")
        func uncappedAndEmpty() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let uncapped = NetworkConditionEffect(profileName: "Slow", latency: .seconds(1), bandwidth: nil, failure: nil)
            let capped = NetworkConditionEffect(profileName: "Capped", latency: .zero, bandwidth: 10, failure: nil)
            let events = OSAllocatedUnfairLock(initialState: [String]())
            let first = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: uncapped, scheduler: scheduler)) { event in
                events.withLock { $0.append(event.line) }
            }
            let second = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: capped, scheduler: scheduler)) { event in
                events.withLock { $0.append(event.line) }
            }
            let url = try #require(URL(string: "https://api.example.com/"))
            let response = try #require(HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil))

            first.deliver(response, body: Data(repeating: 1, count: 5000))
            second.deliver(response, body: Data())

            #expect(events.withLock { $0 } == ["response 204", "data 5000", "finished", "response 204", "finished"])
            #expect(scheduler.snapshot.delays.isEmpty)
        }

        @Test("Cancelled during the latency, the scheduled step is cancelled and nothing is handed on, then or later")
        func cancelDuringLatency() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Down", latency: .seconds(2), bandwidth: nil, failure: .timedOut)
            let events = OSAllocatedUnfairLock(initialState: [String]())
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { event in
                events.withLock { $0.append(event.line) }
            }
            let url = try #require(URL(string: "https://api.example.com/"))

            sut.start(url: url) {}
            scheduler.advance(by: .seconds(1))
            sut.cancel()
            scheduler.advance(by: .seconds(5))
            sut.fail(URLError(.cancelled) as NSError)

            #expect(events.withLock { $0 }.isEmpty)
            #expect(scheduler.snapshot.pendingCount == 0)
            #expect(scheduler.snapshot.cancelledCount == 1)
        }

        @Test("Cancelled partway through a capped body, no more parts and no finish are handed on")
        func cancelDuringBody() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Capped", latency: .zero, bandwidth: 1000, failure: nil)
            let events = OSAllocatedUnfairLock(initialState: [String]())
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { event in
                events.withLock { $0.append(event.line) }
            }
            let url = try #require(URL(string: "https://api.example.com/"))
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))

            sut.deliver(response, body: Data(repeating: 0, count: 1000))
            scheduler.advance(by: .milliseconds(250))
            sut.cancel()
            scheduler.advance(by: .seconds(2))

            #expect(events.withLock { $0 } == ["response 200", "data 100", "data 100"])
            #expect(scheduler.snapshot.pendingCount == 0)
        }

        @Test("A client that cancels from within an event's call hears of nothing after it")
        func cancelFromWithinEvent() throws {
            let scheduler = ManualNetworkConditionScheduler()
            let effect = NetworkConditionEffect(profileName: "Capped", latency: .zero, bandwidth: nil, failure: nil)
            let events = OSAllocatedUnfairLock(initialState: [String]())
            let box = OSAllocatedUnfairLock<NetworkConditionedDelivery?>(initialState: nil)
            let sut = NetworkConditionedDelivery(plan: NetworkConditionPlan(effect: effect, scheduler: scheduler)) { event in
                events.withLock { $0.append(event.line) }
                if case .response = event {
                    box.withLock { $0 }?.cancel()
                }
            }
            box.withLock { $0 = sut }
            let url = try #require(URL(string: "https://api.example.com/"))
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))

            sut.deliver(response, body: Data(repeating: 0, count: 10))

            #expect(events.withLock { $0 } == ["response 200"])
        }
    }

    extension NetworkConditionedDelivery.Event {
        /// The event in a line: "response 200", "data 100", "finished", "failed -1001".
        fileprivate var line: String {
            switch self {
            case let .response(response): "response \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            case let .data(data): "data \(data.count)"
            case .finished: "finished"
            case let .failed(error): "failed \(error.code)"
            }
        }
    }
#endif
