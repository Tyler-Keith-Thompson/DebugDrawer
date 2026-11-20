import CryptoKit
import Foundation

// The user ID is hashed in the process, before anything holds it, with HMAC-SHA256 keyed by 32
// random bytes made on the install's first hash and kept in the app's own defaults (never the app
// group's). The key stays in the app, so the same user hashes to the same value on every launch of
// the install, and a sidecar's reports of that install correlate, while one holding the sidecar or a
// report can't test a guessed ID against the hash: they would need the key, which never leaves the
// app. The key's defaults key starts with `DebugDrawer.`, so Reset App State keeps it.
//
// Rejected: a salt the host provides (compiled into the app, it is the same on every device, so
// anyone with the binary can confirm a guessed ID against a report, and it links one person's
// devices to each other); plain SHA-256 of the ID (user IDs are short and often sequential, so a
// table of hashes reverses them); and the keychain for the key (a test runner on the Mac has none,
// and the key protects nothing the app's own container doesn't already hold, the raw ID included).

/// Hashes a user ID with a key of the install's own.
struct UserIDHasher {
    /// The defaults key the install's hashing key is kept under.
    static let keyDefaultsKey = "DebugDrawer.AppState.userIDKey"

    let defaults: UserDefaults

    /// `userID`'s HMAC-SHA256 under the install's key, as 64 lowercase hexadecimal digits.
    func hash(_ userID: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(userID.utf8), using: key()).hexadecimal
    }

    /// The install's key: the one kept in the defaults, or a new one, kept there.
    private func key() -> SymmetricKey {
        if let kept = defaults.data(forKey: Self.keyDefaultsKey), kept.count == SHA256.byteCount {
            return SymmetricKey(data: kept)
        }
        let key = SymmetricKey(size: .bits256)
        defaults.set(key.withUnsafeBytes { Data($0) }, forKey: Self.keyDefaultsKey)
        return key
    }
}

extension HashedAuthenticationCode {
    /// The code as lowercase hexadecimal, two digits a byte.
    fileprivate var hexadecimal: String {
        let digits = Array("0123456789abcdef")
        var text = ""
        text.reserveCapacity(byteCount * 2)
        for byte in self {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }
}
