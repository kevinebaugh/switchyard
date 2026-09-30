// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Switchyard",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Switchyard", targets: ["Switchyard"]),
    ],
    targets: [
        // Pure routing logic: rules, matching, Jev request/response, decisions, sync merge.
        .target(
            name: "RouterCore",
            path: "Sources/RouterCore"
        ),
        // The menu-bar app: AppKit/SwiftUI, Dia automation, networking, persistence.
        .executableTarget(
            name: "Switchyard",
            dependencies: ["RouterCore"],
            path: "Sources/Switchyard"
        ),
        .testTarget(
            name: "RouterCoreTests",
            dependencies: ["RouterCore"],
            path: "Tests/RouterCoreTests"
        ),
    ]
)
