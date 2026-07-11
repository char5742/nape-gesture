// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NapeGesture",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NapeGestureCore", targets: ["NapeGestureCore"]),
        .executable(name: "nape-gesture", targets: ["nape-gesture"]),
        .executable(name: "nape-gesture-core-tests", targets: ["nape-gesture-core-tests"])
    ],
    targets: [
        .target(name: "NapeGestureCore"),
        .target(
            name: "NapeGestureProductOutput",
            dependencies: ["NapeGestureCore"]
        ),
        .target(
            name: "NapeGestureDiagnosticOutput",
            dependencies: ["NapeGestureCore"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "nape-gesture",
            dependencies: [
                "NapeGestureCore",
                "NapeGestureProductOutput",
                "NapeGestureDiagnosticOutput"
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "nape-gesture-core-tests",
            dependencies: ["NapeGestureCore", "NapeGestureProductOutput"]
        )
    ]
)
