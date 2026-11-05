// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Paste",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Paste", targets: ["Paste"]),
    ],
    targets: [
        .target(
            name: "PasteKit",
            path: "Sources/PasteKit"
        ),
        .executableTarget(
            name: "Paste",
            dependencies: ["PasteKit"],
            path: "Sources/Paste"
        ),
        .testTarget(
            name: "PasteKitTests",
            dependencies: ["PasteKit"],
            path: "Tests/PasteKitTests"
        ),
    ]
)
