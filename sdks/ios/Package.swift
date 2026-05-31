// swift-tools-version: 6.3
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
        .target(
            name: "Coproduct",
            dependencies: ["coproduct_ffi_uniffiFFI"]
        ),
        .testTarget(
            name: "CoproductTests",
            dependencies: ["Coproduct"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
