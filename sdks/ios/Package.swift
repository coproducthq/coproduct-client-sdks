// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coproduct",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Coproduct",
            targets: ["Coproduct"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "coproduct_ffi_uniffiFFI",
            path: "CoproductFFI.xcframework"
        ),
        // Generated UniFFI bindings. Kept in its own target that is deliberately
        // not a library product, so the raw generated surface is hidden by default
        // from code that imports the Coproduct product. This is a discoverability
        // guard, not an enforced boundary: SwiftPM still builds this module into
        // the products directory, so a determined consumer can import it directly
        .target(
            name: "CoproductFFI",
            dependencies: ["coproduct_ffi_uniffiFFI"]
        ),
        .target(
            name: "Coproduct",
            dependencies: ["CoproductFFI"]
        ),
        .testTarget(
            name: "CoproductTests",
            dependencies: ["Coproduct", "CoproductFFI"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
