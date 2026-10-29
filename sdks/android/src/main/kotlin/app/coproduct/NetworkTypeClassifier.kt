package app.coproduct

/**
 * Connectivity facts one network update carries, decoupled from
 * ConnectivityManager so tests can fabricate updates without Android's
 * connectivity stack
 */
internal data class NetworkPathFacts(
    val satisfied: Boolean,
    val wifi: Boolean,
    val cellular: Boolean,
    val ethernet: Boolean,
)

/**
 * Maps path facts to the network_type vocabulary. Pure so the vocabulary and
 * precedence order are unit-testable in isolation
 */
internal object NetworkTypeClassifier {
    fun classify(facts: NetworkPathFacts): String {
        if (!facts.satisfied) return "none"
        return when {
            facts.wifi -> "wifi"
            facts.cellular -> "cellular"
            facts.ethernet -> "ethernet"
            else -> "other"
        }
    }
}
