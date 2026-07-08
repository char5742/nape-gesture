// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MacGesture",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacGestureCore", targets: ["MacGestureCore"]),
        .executable(name: "mac-gesture", targets: ["mac-gesture"]),
        .executable(name: "mac-gesture-core-tests", targets: ["mac-gesture-core-tests"])
    ],
    targets: [
        .target(name: "MacGestureCore"),
        .executableTarget(
            name: "mac-gesture",
            dependencies: ["MacGestureCore"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "mac-gesture-core-tests",
            dependencies: ["MacGestureCore"]
        )
    ]
)
