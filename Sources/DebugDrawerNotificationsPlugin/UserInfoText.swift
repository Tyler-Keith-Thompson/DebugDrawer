#if DEBUG
    import Foundation

    /// A notification's `userInfo` as text: pretty-printed JSON with sorted keys, or the
    /// dictionary's own description when it holds something JSON can't (a date); empty when it
    /// holds nothing.
    struct UserInfoText: Equatable, Sendable {
        let text: String
        /// Whether `text` is JSON, and so can be redacted key by key.
        let isJSON: Bool

        init(text: String, isJSON: Bool) {
            self.text = text
            self.isJSON = isJSON
        }

        init(_ userInfo: [AnyHashable: Any]) {
            if userInfo.isEmpty {
                self.init(text: "", isJSON: false)
            } else if JSONSerialization.isValidJSONObject(userInfo),
                      let data = try? JSONSerialization.data(
                          withJSONObject: userInfo, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                      ),
                      let text = String(bytes: data, encoding: .utf8) {
                self.init(text: text, isJSON: true)
            } else {
                self.init(text: String(describing: userInfo), isJSON: false)
            }
        }
    }
#endif
