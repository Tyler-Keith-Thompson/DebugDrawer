import Foundation

/// An experiment (an A/B test) a sidecar may see: its key, its variants and the variant the app is
/// assigned now.
public struct DebugDrawerExperiment: Codable, Equatable, Sendable {
    /// Identifies the experiment to the experiment service ("checkout-flow").
    public let key: String
    /// The experiment's variants (arms), in the order to list them ("control", "treatment").
    public let variants: [String]
    /// The variant the app is assigned now, an override included, or `nil` when the app isn't
    /// enrolled in the experiment.
    public let assignedVariant: String?

    /// An experiment.
    ///
    /// - Parameters:
    ///   - key: Identifies the experiment to the experiment service.
    ///   - variants: The experiment's variants, in the order to list them.
    ///   - assignedVariant: The variant the app is assigned now, an override included, or `nil`
    ///     when the app isn't enrolled.
    public init(key: String, variants: [String], assignedVariant: String?) {
        self.key = key
        self.variants = variants
        self.assignedVariant = assignedVariant
    }
}
