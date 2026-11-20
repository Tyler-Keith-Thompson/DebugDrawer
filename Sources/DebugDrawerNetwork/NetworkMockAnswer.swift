import Foundation
import UniformTypeIdentifiers

/// What a mock rule answers a request with, ready to send.
package struct NetworkMockAnswer: Equatable, Sendable {
    /// The name of the rule that answered, which the log shows.
    package let ruleName: String
    /// The HTTP status code.
    package let status: Int
    /// The headers, `Content-Length` and `Content-Type` included.
    package let headers: [String: String]
    /// The body.
    package let body: Data
}

package extension NetworkMockRule {
    /// The rule's response with its body read and its headers completed.
    func answer(body read: (String) -> Data?) -> NetworkMockAnswer {
        let body: Data
        var fileType: String?
        switch response.body {
        case .empty:
            body = Data()
        case let .text(text):
            body = Data(text.utf8)
        case let .file(name):
            body = read(name) ?? Data()
            fileType = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType
        }
        return NetworkMockAnswer(
            ruleName: name,
            status: response.status,
            headers: response.headerFields(bodyLength: body.count, fileType: fileType),
            body: body
        )
    }
}

package extension NetworkMockRule.Response {
    /// The headers sent: the rule's own, its content type in place of theirs (or, with neither,
    /// a file's type), and `Content-Length` set to the body's length.
    func headerFields(bodyLength: Int, fileType: String? = nil) -> [String: String] {
        var fields = headers
        if let type = contentType ?? (fields.hasValue(named: "Content-Type") ? nil : fileType) {
            fields.setValue(type, named: "Content-Type")
        }
        fields.setValue(String(bodyLength), named: "Content-Length")
        return fields
    }
}

extension [String: String] {
    /// Whether a header named `name`, in any case, is set.
    fileprivate func hasValue(named name: String) -> Bool {
        keys.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Sets the header named `name`, replacing one of the same name in any case.
    fileprivate mutating func setValue(_ value: String, named name: String) {
        for key in keys where key.caseInsensitiveCompare(name) == .orderedSame {
            removeValue(forKey: key)
        }
        self[name] = value
    }
}
