#if DEBUG
    extension LogLine {
        /// The metadata as a line shows and copies it, after the text: `key=value` fields sorted
        /// by key, a space between (`order=1042 user=7`); `nil` for a line without any.
        var shownMetadata: String? {
            guard !metadata.isEmpty else { return nil }
            return metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }

        /// What a search matches the metadata against: each key, each value, and each field as
        /// shown, `key=value`, so a pattern can anchor on a value or on a whole field.
        var searchableMetadata: [String] {
            metadata.flatMap { [$0.key, $0.value, "\($0.key)=\($0.value)"] }
        }
    }
#endif
