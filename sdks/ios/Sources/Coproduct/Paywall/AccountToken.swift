import CryptoKit
import Foundation

/// The namespace the Coproduct server uses to derive a store account token.
/// Must match the server's value exactly, or the server cannot tell whose
/// purchase a signed transaction is.
private let accountTokenNamespace = UUID(uuidString: "8f1b6c1e-6f0a-4d0e-9a53-2c1d7f4b9e10")!

/// The store account token for an app user: a version 5 UUID (RFC 4122,
/// SHA-1) of the app user id's UTF-8 bytes under `accountTokenNamespace`.
/// Passed to StoreKit as `appAccountToken` at purchase time. The server
/// recomputes it from the app user id to learn which user a purchase was
/// made for.
func accountToken(forAppUserId appUserId: String) -> UUID {
    var input = withUnsafeBytes(of: accountTokenNamespace.uuid) { Data($0) }
    input.append(contentsOf: appUserId.utf8)
    var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}
