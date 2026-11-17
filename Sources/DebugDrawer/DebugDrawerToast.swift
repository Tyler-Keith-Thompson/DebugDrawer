/// A notice a plugin raised, shown while the drawer is closed.
public struct DebugDrawerToast: Equatable, Sendable {
    /// The plugin that raised it.
    public let pluginID: String
    /// The latest message the plugin posted.
    public let message: String
    /// How many posts the toast stands for: a plugin's posts replace its message and add to this.
    public let count: Int
}
