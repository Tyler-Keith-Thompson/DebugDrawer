#if DEBUG
    import Foundation
    import Security

    // The words the views show for a refusal. Kept apart from the values: the snapshot carries the
    // status and the action, and whoever draws it words them.

    extension KeychainError {
        /// Security's own words for the status, with its code ("A required entitlement isn't
        /// present. (-34018)").
        var message: String {
            let text = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "Keychain error"
            return "\(text) (\(status))"
        }
    }

    extension KeychainIssue {
        /// What was being done, then why the keychain refused ("Couldn't save: …").
        var message: String {
            "\(action): \(error.message)"
        }
    }
#endif
