import Foundation

extension Data {
    /// The bytes as lowercase hexadecimal, two digits each, as push services take a device token.
    package var hexadecimal: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
