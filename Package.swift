// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FileViewer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "FileViewer", targets: ["FileViewer"])
    ],
    targets: [
        .executableTarget(
            name: "FileViewer",
            path: "Sources/FileViewer"
        )
    ]
)
