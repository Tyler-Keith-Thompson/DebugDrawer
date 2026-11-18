#if DEBUG
    /// How many cookies the filter shows, of how many the stores hold.
    struct CookieCount: Hashable, Sendable {
        let shown: Int
        let total: Int

        /// Whether the filter hides any.
        var isFiltered: Bool {
            shown != total
        }

        /// "12 cookies", or "3 of 12 cookies" while the filter hides some.
        var label: String {
            isFiltered ? "\(shown) of \(Self.cookies(total))" : Self.cookies(total)
        }

        /// What Delete All asks before deleting: every cookie, or the ones the filter shows.
        var deleteQuestion: String {
            if isFiltered {
                shown == 1 ? "Delete the cookie the filter shows?" : "Delete the \(shown) cookies the filter shows?"
            } else {
                total == 1 ? "Delete the only cookie?" : "Delete all \(total) cookies?"
            }
        }

        /// What Delete All will and won't touch.
        var deleteExplanation: String {
            let stores = "Each is deleted from the store it is in."
            guard isFiltered else { return stores }
            let hidden = total - shown
            return "\(stores) The \(hidden == 1 ? "one" : "\(hidden)") the filter hides \(hidden == 1 ? "stays" : "stay")."
        }

        private static func cookies(_ count: Int) -> String {
            count == 1 ? "1 cookie" : "\(count) cookies"
        }
    }
#endif
