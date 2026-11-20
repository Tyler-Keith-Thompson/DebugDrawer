import Combine
import Foundation

/// Times one conditioned request: waits out the latency, then fails the request as its plan
/// says or lets it proceed, and delivers the answer's body no faster than the bandwidth cap.
/// Each step is scheduled through the plan's scheduler and handed on as an event, in order.
///
/// Once cancelled it hands on nothing more, and the work it had scheduled is cancelled.
package final class NetworkConditionedDelivery: @unchecked Sendable {
    /// What the request's client is told, in the order it is told.
    package enum Event {
        case response(URLResponse)
        case data(Data)
        case finished
        case failed(NSError)
    }

    /// How many parts a second a capped body arrives in.
    package static let chunksPerSecond = 10

    private let plan: NetworkConditionPlan
    private let emit: @Sendable (Event) -> Void
    // Recursive, so a client told of an event can stop the request from within the call
    // without waiting on itself. A step checks for cancellation and hands its event on while
    // holding the lock, so `cancel()` returns only once no step can hand on another event.
    private let lock = NSRecursiveLock()
    // Guarded by `lock`.
    private var isCancelled = false
    private var pending: AnyCancellable?

    /// - Parameters:
    ///   - plan: The effect to apply and the scheduler that times it.
    ///   - emit: Hands each event on to the request's client.
    package init(plan: NetworkConditionPlan, emit: @escaping @Sendable (Event) -> Void) {
        self.plan = plan
        self.emit = emit
    }

    /// Waits out the latency, then fails the request as the plan says, or calls `proceed`,
    /// which answers it with ``deliver(_:body:)`` or ``fail(_:)``. A failure comes after the
    /// latency, as a real timeout or lost connection takes time to show.
    ///
    /// - Parameter url: The request's URL, which a synthesized response carries.
    package func start(url: URL, proceed: @escaping @Sendable () -> Void) {
        after(plan.effect.latency) { [self] in
            switch plan.effect.failure {
            case .timedOut:
                send(.failed(URLError(.timedOut) as NSError))
            case .notConnectedToInternet:
                send(.failed(URLError(.notConnectedToInternet) as NSError))
            case .internalServerError:
                // `HTTPURLResponse`'s initializer returns nil only for a URL it can't use, and
                // the request's own URL was usable.
                let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "0"])
                if let response {
                    send(.response(response))
                }
                send(.finished)
            case nil:
                proceed()
            }
        }
    }

    /// Delivers `response` at once, then `body` in parts no faster than the plan's bandwidth
    /// cap, then the finish; with no cap, all of it at once.
    ///
    /// - Complexity: O(*n*) parts for a body that takes *n* tenths of a second at the cap.
    package func deliver(_ response: URLResponse, body: Data) {
        guarded {
            send(.response(response))
            sendChunks(of: body, from: body.startIndex)
        }
    }

    /// Hands on `error` as the request's end.
    package func fail(_ error: NSError) {
        guarded {
            send(.failed(error))
        }
    }

    /// Stops: the scheduled step is cancelled, and nothing more is handed on.
    package func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        pending?.cancel()
        pending = nil
    }

    // MARK: Steps

    /// Sends the part of `body` from `offset`, then schedules the next, or finishes.
    private func sendChunks(of body: Data, from offset: Data.Index) {
        guard offset < body.endIndex else {
            send(.finished)
            return
        }
        guard let bandwidth = plan.effect.bandwidth else {
            send(.data(body[offset...]))
            send(.finished)
            return
        }
        let size = Swift.max(bandwidth / Self.chunksPerSecond, 1)
        let end = body.index(offset, offsetBy: size, limitedBy: body.endIndex) ?? body.endIndex
        // Duration's own integer arithmetic, in attoseconds, so a part's time is exact rather
        // than a rounded fraction, and a large cap can't overflow.
        let delay = Duration.seconds(1) * (end - offset) / bandwidth
        after(delay) { [self] in
            send(.data(body[offset ..< end]))
            sendChunks(of: body, from: end)
        }
    }

    /// Runs `step` after `delay` under the lock, unless cancelled first; at once for no delay.
    private func after(_ delay: Duration, _ step: @escaping @Sendable () -> Void) {
        guard delay > .zero else {
            guarded(step)
            return
        }
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        pending = plan.scheduler.schedule(after: delay) { [self] in
            guarded(step)
        }
    }

    /// Hands `event` on, unless cancelled: a client told of an earlier event in the same step
    /// may have stopped the request. Called holding the lock.
    private func send(_ event: Event) {
        guard !isCancelled else { return }
        emit(event)
    }

    /// Runs `body` holding the lock, unless cancelled.
    private func guarded(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        body()
    }
}
