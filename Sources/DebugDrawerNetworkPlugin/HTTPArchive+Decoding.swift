#if DEBUG
    import Foundation

    // Archives from browsers and proxies (Chrome DevTools, Charles, Proxyman) leave out fields the
    // format calls optional, and some it calls required (cookies, timings, sizes), and add their own
    // (`pages`, `_initiator`, `_resourceType`). Each decoder here reads what is there, ignores what
    // it doesn't know, and fills a missing value with the format's "unknown": `-1` for a size or a
    // time, and empty for text and lists. Only an entry's request method and URL are required.

    extension HTTPArchive.Log {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case version, creator, entries
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
            creator = try container.decodeIfPresent(HTTPArchive.Creator.self, forKey: .creator) ?? HTTPArchive.Creator(name: "", version: "")
            entries = try container.decode([HTTPArchive.Entry].self, forKey: .entries)
        }
    }

    extension HTTPArchive.Creator {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case name, version
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        }
    }

    extension HTTPArchive.NameValue {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case name, value
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        }
    }

    extension HTTPArchive.Cookie {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case name, value, path, domain, expires, httpOnly, secure
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
            path = try? container.decodeIfPresent(String.self, forKey: .path)
            domain = try? container.decodeIfPresent(String.self, forKey: .domain)
            // Chrome writes `expires: null` for a session cookie, others a date or nothing.
            expires = try? container.decodeIfPresent(String.self, forKey: .expires)
            httpOnly = try? container.decodeIfPresent(Bool.self, forKey: .httpOnly)
            secure = try? container.decodeIfPresent(Bool.self, forKey: .secure)
        }
    }

    extension HTTPArchive.PostData {
        /// The spelling a tool may use for the encoding instead of the custom `_encoding`.
        private enum StandardKeys: String, CodingKey {
            case encoding
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let standard = try decoder.container(keyedBy: StandardKeys.self)
            mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
                ?? standard.decodeIfPresent(String.self, forKey: .encoding)
        }
    }

    extension HTTPArchive.Request {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case method, url, httpVersion, cookies, headers, queryString, postData, headersSize, bodySize
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            method = try container.decode(String.self, forKey: .method)
            url = try container.decode(String.self, forKey: .url)
            httpVersion = try container.decodeIfPresent(String.self, forKey: .httpVersion) ?? ""
            cookies = try container.decodeIfPresent([HTTPArchive.Cookie].self, forKey: .cookies) ?? []
            headers = try container.decodeIfPresent([HTTPArchive.NameValue].self, forKey: .headers) ?? []
            queryString = try container.decodeIfPresent([HTTPArchive.NameValue].self, forKey: .queryString) ?? []
            postData = try container.decodeIfPresent(HTTPArchive.PostData.self, forKey: .postData)
            headersSize = try container.decodeIfPresent(Int.self, forKey: .headersSize) ?? -1
            bodySize = try container.decodeIfPresent(Int.self, forKey: .bodySize) ?? -1
        }
    }

    extension HTTPArchive.Content {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case size, mimeType, text, encoding
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            size = try container.decodeIfPresent(Int.self, forKey: .size) ?? -1
            mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
            text = try container.decodeIfPresent(String.self, forKey: .text)
            encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
        }
    }

    extension HTTPArchive.Response {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case status, statusText, httpVersion, cookies, headers, content, redirectURL, headersSize, bodySize
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
            statusText = try container.decodeIfPresent(String.self, forKey: .statusText) ?? ""
            httpVersion = try container.decodeIfPresent(String.self, forKey: .httpVersion) ?? ""
            cookies = try container.decodeIfPresent([HTTPArchive.Cookie].self, forKey: .cookies) ?? []
            headers = try container.decodeIfPresent([HTTPArchive.NameValue].self, forKey: .headers) ?? []
            content = try container.decodeIfPresent(HTTPArchive.Content.self, forKey: .content)
                ?? HTTPArchive.Content(size: -1, mimeType: "")
            redirectURL = try container.decodeIfPresent(String.self, forKey: .redirectURL) ?? ""
            headersSize = try container.decodeIfPresent(Int.self, forKey: .headersSize) ?? -1
            bodySize = try container.decodeIfPresent(Int.self, forKey: .bodySize) ?? -1
        }
    }

    extension HTTPArchive.Timings {
        // Declared, not synthesized, so the decoder in this file can name them.
        enum CodingKeys: String, CodingKey {
            case blocked, dns, connect, ssl, send, wait, receive
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            blocked = try container.decodeIfPresent(Double.self, forKey: .blocked) ?? -1
            dns = try container.decodeIfPresent(Double.self, forKey: .dns) ?? -1
            connect = try container.decodeIfPresent(Double.self, forKey: .connect) ?? -1
            ssl = try container.decodeIfPresent(Double.self, forKey: .ssl) ?? -1
            send = try container.decodeIfPresent(Double.self, forKey: .send) ?? -1
            wait = try container.decodeIfPresent(Double.self, forKey: .wait) ?? -1
            receive = try container.decodeIfPresent(Double.self, forKey: .receive) ?? -1
        }
    }

    extension HTTPArchive.Entry {
        /// Where Chrome DevTools puts a failed request's error: in the response.
        private enum ResponseKeys: String, CodingKey {
            case response
        }

        private enum ResponseErrorKeys: String, CodingKey {
            case error = "_error"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startedDateTime = try container.decodeIfPresent(String.self, forKey: .startedDateTime) ?? ""
            time = try container.decodeIfPresent(Double.self, forKey: .time) ?? -1
            request = try container.decode(HTTPArchive.Request.self, forKey: .request)
            response = try container.decodeIfPresent(HTTPArchive.Response.self, forKey: .response)
                ?? HTTPArchive.Response(status: 0, statusText: "", httpVersion: "", headers: [], content: .init(size: -1, mimeType: ""), bodySize: -1)
            cache = try container.decodeIfPresent(HTTPArchive.Cache.self, forKey: .cache) ?? HTTPArchive.Cache()
            timings = try container.decodeIfPresent(HTTPArchive.Timings.self, forKey: .timings)
                ?? HTTPArchive.Timings(dns: -1, connect: -1, ssl: -1, send: -1, wait: -1, receive: -1)
            let responseError = try? decoder.container(keyedBy: ResponseKeys.self)
                .nestedContainer(keyedBy: ResponseErrorKeys.self, forKey: .response)
                .decodeIfPresent(String.self, forKey: .error)
            // Chrome writes an empty `_error` for a request that didn't fail.
            error = try (container.decodeIfPresent(String.self, forKey: .error) ?? responseError).flatMap { $0.isEmpty ? nil : $0 }
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }
    }
#endif
