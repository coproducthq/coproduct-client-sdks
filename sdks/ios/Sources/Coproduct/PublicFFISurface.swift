// Deliberate public re-exports of the generated types that are genuinely part of
// the SDK's public contract. The generated bindings live in the CoproductFFI
// target, which is not a library product, so the raw generated surface (the
// top-level initialize, CoproductClient, FfiConfig, bucketForVectors, the
// converters, and the handle types) stays out of the Coproduct module and out of
// autocomplete for code that imports Coproduct.
//
// This is hidden by default, not an enforced boundary. SwiftPM builds every
// target's module into the products directory regardless of product membership,
// so a determined consumer can still write `import CoproductFFI` and reach those
// symbols. Treat the split as a discoverability guard, and never rely on it for
// anything security-shaped.
//
// Per-declaration @_exported import is used instead of typealiases because these
// types are enums and structs whose cases and members consumers must access (for
// example ProviderState.notReady or CoproductSnapshot.version). A typealias would
// re-expose only the name, not the members. @_exported is an underscored,
// officially unsupported attribute, accepted here as a deliberate risk because
// there is no stable equivalent for member-preserving per-declaration re-export.
// Add a line here only when a generated type genuinely joins the public contract,
// and never re-export the raw entry points.

// Host capability protocols a developer implements
@_exported import protocol CoproductFFI.HostTransport
@_exported import protocol CoproductFFI.HostSecureStore
@_exported import protocol CoproductFFI.EvaluationListener

// Values the transport protocol traffics in
@_exported import struct CoproductFFI.HttpRequest
@_exported import struct CoproductFFI.HttpResponse
@_exported import struct CoproductFFI.HttpHeader
@_exported import enum CoproductFFI.HttpMethod
@_exported import enum CoproductFFI.TransportError

// Error a secure store implementation throws
@_exported import enum CoproductFFI.SecureStoreError

// The event an evaluation listener receives, and the types it exposes
@_exported import struct CoproductFFI.EvaluationEvent
@_exported import enum CoproductFFI.EvaluationReason
@_exported import enum CoproductFFI.FlagType
@_exported import enum CoproductFFI.FlagValue

// Values the top-level API returns
@_exported import enum CoproductFFI.LifecycleEvent
@_exported import enum CoproductFFI.ProviderState
@_exported import struct CoproductFFI.CoproductSnapshot
