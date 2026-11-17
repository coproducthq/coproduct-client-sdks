package app.coproduct.paywall

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

// The namespace every Coproduct SDK and the server derive store account
// tokens under. Changing it orphans every token already stored with a purchase
private val ACCOUNT_TOKEN_NAMESPACE: UUID = UUID.fromString("8f1b6c1e-6f0a-4d0e-9a53-2c1d7f4b9e10")

/**
 * The store account token for [appUserId]: an RFC 4122 version 5 (SHA-1)
 * UUID of the id's UTF-8 bytes under the Coproduct namespace, as a lowercase
 * hyphenated string. PlayBillingPaywallBridge hands it to Play Billing as the
 * purchase's obfuscatedAccountId, and the server recomputes it to learn which
 * app user a purchase was made for. Not java.util.UUID.nameUUIDFromBytes,
 * which is version 3 (MD5) and yields a different value.
 */
internal fun accountToken(appUserId: String): String {
    val digest = MessageDigest.getInstance("SHA-1")
    digest.update(
        ByteBuffer.allocate(16)
            .putLong(ACCOUNT_TOKEN_NAMESPACE.mostSignificantBits)
            .putLong(ACCOUNT_TOKEN_NAMESPACE.leastSignificantBits)
            .array()
    )
    val hash = digest.digest(appUserId.toByteArray(Charsets.UTF_8))
    hash[6] = ((hash[6].toInt() and 0x0f) or 0x50).toByte() // version 5
    hash[8] = ((hash[8].toInt() and 0x3f) or 0x80).toByte() // RFC 4122 variant
    val bytes = ByteBuffer.wrap(hash, 0, 16)
    return UUID(bytes.long, bytes.long).toString()
}
