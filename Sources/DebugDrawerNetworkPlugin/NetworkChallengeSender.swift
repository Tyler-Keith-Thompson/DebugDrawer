#if DEBUG
    import Foundation
    import os

    /// The sender of an authentication challenge the forwarded request met (a server's
    /// certificate, a password, a client certificate), handed to the app's task so the app's own
    /// session delegate answers it: whatever the delegate decides goes back to the forwarded
    /// request as its answer.
    final class NetworkChallengeSender: NSObject, URLAuthenticationChallengeSender, Sendable {
        typealias Answer = @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

        /// The forwarded request's completion handler until the first answer; later answers do
        /// nothing, as the handler may be called once.
        private let answer: OSAllocatedUnfairLock<Answer?>

        /// - Parameter answer: The forwarded request's completion handler for the challenge.
        init(answer: @escaping Answer) {
            self.answer = OSAllocatedUnfairLock(initialState: answer)
        }

        func use(_ credential: URLCredential, for _: URLAuthenticationChallenge) {
            reply(.useCredential, credential)
        }

        func continueWithoutCredential(for _: URLAuthenticationChallenge) {
            reply(.useCredential, nil)
        }

        func cancel(_: URLAuthenticationChallenge) {
            reply(.cancelAuthenticationChallenge, nil)
        }

        func performDefaultHandling(for _: URLAuthenticationChallenge) {
            reply(.performDefaultHandling, nil)
        }

        func rejectProtectionSpaceAndContinue(with _: URLAuthenticationChallenge) {
            reply(.rejectProtectionSpace, nil)
        }

        /// Cancels the challenge if the app never answered it, as when its task stopped first.
        func cancelUnanswered() {
            reply(.cancelAuthenticationChallenge, nil)
        }

        private func reply(_ disposition: URLSession.AuthChallengeDisposition, _ credential: URLCredential?) {
            let pending = answer.withLock { answer in
                defer { answer = nil }
                return answer
            }
            pending?(disposition, credential)
        }
    }
#endif
