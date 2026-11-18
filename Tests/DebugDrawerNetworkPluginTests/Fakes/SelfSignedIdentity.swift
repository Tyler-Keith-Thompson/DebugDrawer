#if DEBUG
    import Foundation
    import Security

    /// A self-signed certificate for `localhost` and 127.0.0.1, valid until 2126, and its RSA key,
    /// made for these tests alone (`openssl req -x509 -newkey rsa:2048`). The identity is built in
    /// memory (`SecIdentityCreate`): nothing is added to any keychain.
    enum SelfSignedIdentity {
        /// The certificate, DER-encoded: what a pinning delegate compares the server's leaf with.
        static let certificateData = Data(base64Encoded: certificateBase64, options: .ignoreUnknownCharacters) ?? Data()

        /// The certificate and its key, for a TLS server.
        static func make() throws -> SecIdentity {
            guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData),
                  let keyData = Data(base64Encoded: keyBase64, options: .ignoreUnknownCharacters)
            else { throw IdentityError() }
            let attributes = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary
            guard let key = SecKeyCreateWithData(keyData as CFData, attributes, nil),
                  let identity = SecIdentityCreate(nil, certificate, key)
            else { throw IdentityError() }
            return identity
        }

        struct IdentityError: Error {}

        private static let certificateBase64 = """
            MIIDBjCCAe6gAwIBAgIUd4IUTf8XWicyadQXFy6jVMsvg1IwDQYJKoZIhvcNAQELBQAwFDESMBAGA1UEAwwJbG9jYWxob3N0
            MCAXDTI2MTExODIyNDkxNVoYDzIxMjYxMDI1MjI0OTE1WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEB
            AQUAA4IBDwAwggEKAoIBAQDBm13DiPLfAkGkjte84BcBrYrvwIMW8ZpDOTtdNvMNp+zLkjv40H/IygYFeUpGvfJYhBAvOrS7
            ywDnZdxj+i2jsttdqpcLOwnTd1YIke9t4PGdpmUXbfqibOg5O3VsU4t3OwBp/ulHzwnU4rdjhKTwGUJ12xTadBKOiXNtBmmI
            Zhe/6KVJKUaY08OQZKvtRl5qtGchDLKONV3u7OVb0jWCIOpGKPu8zFOQXZGYAsTeqn+JgkJkO8rHFQAuYUC7xNcmUKf511NM
            6YLOHz06Qd+ZbETrfbjnnllMoUU7qY65npXzRLlfYKc+3rbq0mAITKhuL68qZGrEnyanCiNXT8NtAgMBAAGjTjBMMB0GA1Ud
            DgQWBBQuctRnAfd03ZdyVUVt+iNWHOWImTAPBgNVHRMBAf8EBTADAQH/MBoGA1UdEQQTMBGCCWxvY2FsaG9zdIcEfwAAATAN
            BgkqhkiG9w0BAQsFAAOCAQEAkJrvehKARbFmBEiH1FMtfvSHumG2lX4MQ7zbEpYyY+uNE4cV0IeqGyJrQDfA9C7a5/jqSPSn
            JWfYr47yd3uxzuh7Pd96QYixK+RIQb+Z9K5zgFcv2PnQ/1mDkCIqnywW6qduRMOf+n/gwYMoQ6LaYCAOmycF/urap3iesJrj
            LICeF1oy14EqaMgV+6TuwTxuBwQ1tkTpbbmMBClL1YDyjZ2hfd1jbeOjgnWmVDN+7bwC2IMtWJpfUeHLrwPb3LqLXg9IjuO6
            B38s7gHtlzI1LlRUPy8gSKEG8qFr4KmLPnX2fj4YdUGs0G6Q6F4sYrm37urkTrfk/4X/RY8+dPGQgA==
            """

        /// The key in PKCS #1 form (`openssl rsa -traditional -outform DER`), as
        /// `SecKeyCreateWithData` takes an RSA key.
        private static let keyBase64 = """
            MIIEpAIBAAKCAQEAwZtdw4jy3wJBpI7XvOAXAa2K78CDFvGaQzk7XTbzDafsy5I7+NB/yMoGBXlKRr3yWIQQLzq0u8sA52Xc
            Y/oto7LbXaqXCzsJ03dWCJHvbeDxnaZlF236omzoOTt1bFOLdzsAaf7pR88J1OK3Y4Sk8BlCddsU2nQSjolzbQZpiGYXv+il
            SSlGmNPDkGSr7UZearRnIQyyjjVd7uzlW9I1giDqRij7vMxTkF2RmALE3qp/iYJCZDvKxxUALmFAu8TXJlCn+ddTTOmCzh89
            OkHfmWxE6324555ZTKFFO6mOuZ6V80S5X2CnPt626tJgCEyobi+vKmRqxJ8mpwojV0/DbQIDAQABAoIBAAFChSsSUZqPZrwF
            3O91PkbMDekljs32z001U8++lGbRKz8fvCmruWCTyopPplmxSGDBuKw9bxe3mrYmxMlEelHotAI7tNdp+XjuIB5yFhfPDvSW
            IltX2kLaGu5SaTFzlib/Aa+lvy6DMVomUxpkgNOMbxoscfevzlGJM6eMN73NE+/DAsof8jU0YuSUOxUGvd5KwO6v1HXwnENH
            vMQSFm80OotySEb9JiVpiypN8p3b7H0IaVVfvNU9EM0A9AVUoK9KJzHF206mtUtw994qEZpoMk3K7YesTG762F6ChyLU2MML
            H5ReydMYMiFt9B3kP4yXODe/3Th4Ry0iuzXiVIkCgYEA8ilrM+zuSsAWFDawOLIrrShf2mOdwlQw01b1uLE2u370903UlpAL
            t8wQJYv7F59M1E/9GCFo3wDffeS+J0mCjaqHjyakcMK528Ahzy5TdRqwKV1mvyoBPCTRR8ebh0mQ5veR7BIl/hMCf7vsbi+s
            p4YdyPu2TFKellYZDwX66ZUCgYEAzKujgjcmZVeJmDemdgj6o/Jl0sXv6TnIOD+uQUxt2hjl/sjs3KPjiXFZZxQhXWWhl7LW
            egjliMNVMXb/w6vMEIyKcOsX/tsLN72hOq+BC+aC6T6rkRSbnRA76uN9qKJhaPzA5iyoPvLHLXtiTfRGua0wF7lyYxsnmglv
            Rj5a7HkCgYEApEFt4sGx/GgAUeOqcjqAH6rEIZjyOA7tM1zHvWgOzOzXciuLqDi6igfTZ/Rj82jtLxG2hbibrq+j6HvQc0uM
            T1U9L98xKP8cHC9df29X0pWwqc4d1ErEnawHfF2rY/+FVvTUOMEynfz88/Fe9HpH7TWuXFZIF8ruoOBzjNoskGUCgYAyJ619
            733dP8JcJucH7dNd8by6Ff9gq+RAxHozTkNtOsTB1wMUXqUXvUsnU2uJs6oRvqWIaj21cgiigoLStHrhY09ZtILA1XS+SB4G
            f5OkEuzps43fk6k+qAfG29CjToeIbsfmn/Lq2hutLZs9dysNvT8X0T4Sw0jFGqLGF+m4IQKBgQCWg+FiVIVycsTJ2JYFphJ1
            px9+grKWw0Iy/aiwsIeOLXNRaSi2NxT5d6sLWh7eArAyYfeVjEnn9/6ivnHuzyMCy8nZ5EtUK1BR76M4q6njYMjjeolle9a4
            22MryUmyRX7A9nQeE06uCwfR/KykMY1Q0Zgxo9SW1qWJk0vy/9KNbA==
            """
    }
#endif
