// Compiled (not executed) to prove the typed getters and the per-type details
// records exported over UniFFI are reachable from Swift with the expected call
// shape and field names. If this typechecks, the binding surface is correct

import Foundation

func proveTypedGettersCompile(client: CoproductClient) {
    let _: Bool = client.getBool(key: "k", defaultValue: false)
    let _: String = client.getString(key: "k", defaultValue: "fb")
    let _: Int64 = client.getInt(key: "k", defaultValue: 0)
    let _: Double = client.getNumber(key: "k", defaultValue: 0.0)
    let _: String = client.getJson(key: "k", defaultValueJson: "null")

    let b: FlagEvaluationDetailsBool = client.getBoolDetails(key: "k", defaultValue: false)
    let _: Bool = b.value
    let _: String? = b.variant
    let _: String = b.reason
    let _: String? = b.errorCode
    let _: String? = b.errorMessage
    let _: String = b.flagKey

    let _: FlagEvaluationDetailsString = client.getStringDetails(key: "k", defaultValue: "fb")
    let _: FlagEvaluationDetailsInt = client.getIntDetails(key: "k", defaultValue: 0)
    let _: FlagEvaluationDetailsNumber = client.getNumberDetails(key: "k", defaultValue: 0.0)

    let j: FlagEvaluationDetailsJson = client.getJsonDetails(key: "k", defaultValueJson: "null")
    let _: String = j.valueJson
}
