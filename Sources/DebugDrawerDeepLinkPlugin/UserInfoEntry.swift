#if DEBUG
    /// One key of an activity's userInfo and its value.
    struct UserInfoEntry: Hashable, Codable, Sendable {
        var key: String
        var value: UserInfoValue
    }
#endif
