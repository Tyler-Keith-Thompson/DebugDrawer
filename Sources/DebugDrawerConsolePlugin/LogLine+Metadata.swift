#if DEBUG
    import DebugDrawer

    extension LogLine {
        /// The metadata as a line shows it, after the text: `key=value` fields sorted
        /// by key, a space between (`order=1042 user=7`); `nil` for a line without any.
        var shownMetadata: String? {
            joinedMetadata { $1 }
        }

        /// The metadata as the line copies it: as shown, with the value of each field whose key
        /// contains one of `redaction`'s key patterns masked, and the pairs in the other values
        /// masked as in text (``DebugDrawerRedaction/redacting(text:)``); `nil` for a line without
        /// any.
        func copiedMetadata(redactedBy redaction: DebugDrawerRedaction) -> String? {
            joinedMetadata { key, value in
                redaction.masksKey(key) ? DebugDrawerRedaction.mask : redaction.redacting(text: value)
            }
        }

        /// The fields sorted by key, each `key=value` with the value `value` makes, a space between.
        private func joinedMetadata(_ value: (_ key: String, _ value: String) -> String) -> String? {
            guard !metadata.isEmpty else { return nil }
            return metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\(value($0.key, $0.value))" }.joined(separator: " ")
        }

        /// What a search matches the metadata against: each key, each value, and each field as
        /// shown, `key=value`, so a pattern can anchor on a value or on a whole field.
        var searchableMetadata: [String] {
            metadata.flatMap { [$0.key, $0.value, "\($0.key)=\($0.value)"] }
        }
    }
#endif
