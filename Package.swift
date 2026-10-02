// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Switchyard",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "Switchyard", targets: ["Switchyard"]),
    ],
    dependencies: [
        // In-app updates. Keep in step with scripts/sparkle-tools.sh.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
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
            dependencies: [
                "RouterCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Switchyard",
            // Sparkle.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "RouterCoreTests",
            dependencies: ["RouterCore"],
            path: "Tests/RouterCoreTests"
        ),
    ]
)
