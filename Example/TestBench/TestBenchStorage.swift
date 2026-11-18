import Foundation
import Security
#if canImport(WebKit)
    import WebKit
#endif

/// Writes the storage plugins show: files for Disk I/O and File Browser, keys for UserDefaults, a
/// password for Keychain and cookies for HTTP Cookies.
@MainActor
enum TestBenchStorage {
    /// The folder under Caches the file actions use.
    static var folder: URL {
        URL.cachesDirectory.appending(path: "TestBench", directoryHint: .isDirectory)
    }

    /// On the main thread, which Disk I/O flags: makes the folder, writes a file through `NSData`,
    /// reads it back, lists the folder, then reads a file that isn't there, which Disk I/O lists as
    /// a failure. The file stays for File Browser.
    static func mainThreadFileIO() async -> String {
        let file = folder.appending(path: "written-on-main-thread.json")
        let contents = NSData(data: Data(#"{"writtenAt":"\#(Date.now.formatted(.iso8601))"}"#.utf8))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try contents.write(to: file, options: .atomic)
            let read = try NSData(contentsOf: file, options: [])
            let listed = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            let missing = try? NSData(contentsOf: folder.appending(path: "missing.json"), options: [])
            return "Wrote and read \(read.length) bytes, listed \(listed.count) files, missed one: \(missing == nil)"
        } catch {
            return error.localizedDescription
        }
    }

    /// Sets a date and a dictionary in the standard defaults, as the app's own code would.
    static func writeDefaults() async -> String {
        UserDefaults.standard.set(Date.now, forKey: "testBenchLastRun")
        UserDefaults.standard.set(["source": "Test Bench", "count": 1] as [String: Any], forKey: "testBenchSettings")
        return "Set testBenchLastRun and testBenchSettings"
    }

    /// Replaces a generic password in the data protection keychain, which the Keychain plugin reads.
    /// Run it in the simulator: on a Mac it would reach the developer's own keychain if the app had
    /// a keychain entitlement; without one it fails with errSecMissingEntitlement.
    static func addKeychainPassword() async -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.debugdrawer.example.testbench",
            kSecAttrAccount as String: "test-bench-user",
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data("test-bench-secret".utf8)
        item[kSecAttrLabel as String] = "Test bench password"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status != errSecSuccess else { return "Added test-bench-user" }
        return SecCopyErrorMessageString(status, nil).map { "\($0)" } ?? "OSStatus \(status)"
    }

    /// Sets a session cookie and one that expires in a day in `HTTPCookieStorage.shared`, and one in
    /// WebKit's default store where WebKit exists.
    static func setCookies() async -> String {
        let cookies = [
            HTTPCookie(properties: [.name: "testBenchSession", .value: "abc123", .domain: "example.com", .path: "/"]),
            HTTPCookie(properties: [
                .name: "testBenchRemember", .value: "yes", .domain: ".example.com", .path: "/",
                .expires: Date.now.addingTimeInterval(86400), .secure: "TRUE"
            ])
        ].compactMap(\.self)
        cookies.forEach(HTTPCookieStorage.shared.setCookie)
        #if canImport(WebKit)
            if let webCookie = HTTPCookie(properties: [.name: "testBenchWebView", .value: "web", .domain: "example.com", .path: "/"]) {
                await WKWebsiteDataStore.default().httpCookieStore.setCookie(webCookie)
                return "Set \(cookies.count) in HTTPCookieStorage and 1 in WebKit's store"
            }
        #endif
        return "Set \(cookies.count) in HTTPCookieStorage"
    }
}
