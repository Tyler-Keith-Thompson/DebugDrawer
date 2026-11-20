import Foundation

/// How one request is conditioned: the effect to apply, decided when the request starts, and
/// the scheduler that times it.
package struct NetworkConditionPlan: Sendable {
    /// What the profile does to the request.
    package let effect: NetworkConditionEffect
    /// What times its latency and bandwidth cap.
    package let scheduler: any NetworkConditionScheduler

    /// - Parameters:
    ///   - effect: What the profile does to the request.
    ///   - scheduler: What times it.
    package init(effect: NetworkConditionEffect, scheduler: any NetworkConditionScheduler) {
        self.effect = effect
        self.scheduler = scheduler
    }
}

package extension NetworkConditionProfile {
    /// The profile's effect on one request, rolling `random` for whether it fails when the rate
    /// is neither 0 nor 100.
    func effect(failing random: any NetworkConditionRandomSource) -> NetworkConditionEffect {
        let fails = switch failureRate {
        case ...0: false
        case 100...: true
        default: random.rollPercent() < failureRate
        }
        return NetworkConditionEffect(
            profileName: name,
            latency: max(latency, .zero),
            // A failed request has no body to cap.
            bandwidth: fails ? nil : bandwidth.flatMap { $0 > 0 ? $0 : nil },
            failure: fails ? failure : nil
        )
    }
}
