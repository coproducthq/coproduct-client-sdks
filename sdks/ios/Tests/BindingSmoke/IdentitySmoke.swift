// Compiled (not executed) to prove the identity mutators and the previous
// anonymous id accessor exported over UniFFI are reachable from Swift with the
// expected call shape, parameter labels, and ContextValue case spelling. If this
// typechecks, the identity binding surface is correct

import Foundation

func proveIdentitySurfaceCompiles(client: CoproductClient) async throws {
    try await client.identify(userId: "u", attributes: [:], linkAnonymous: true)
    await client.signOut()
    try await client.setContext(targetingKey: "u", attributes: ["k": .string(value: "v")])
    await client.updateAttributes(attributes: [:])
    await client.removeAttributes(names: ["k"])
    let _: String? = client.previousAnonymousId()
}
