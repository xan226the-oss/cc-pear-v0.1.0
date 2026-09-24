// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "cc-pear",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cc-pear", targets: ["ClipboardShelf"])
    ],
    targets: [
        .executableTarget(
            name: "ClipboardShelf",
            path: "Sources/ClipboardShelf"
        )
    ]
)
