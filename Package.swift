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
        .executable(name: "nape-gesture-core-tests", targets: ["nape-gesture-core-tests"]),
        .executable(
            name: "nape-gesture-product-output-tests",
            targets: ["nape-gesture-product-output-tests"]
        ),
        .executable(
            name: "nape-gesture-diagnostic-output-tests",
            targets: ["nape-gesture-diagnostic-output-tests"]
        )
    ],
    targets: [
        .target(name: "NapeGestureCore"),
        .target(
            name: "NapeGestureProductOutput",
            dependencies: ["NapeGestureCore"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit")
            ]
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
        ),
        .executableTarget(
            name: "nape-gesture-product-output-tests",
            dependencies: ["NapeGestureCore", "NapeGestureProductOutput"],
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "nape-gesture-diagnostic-output-tests",
            dependencies: ["NapeGestureCore", "NapeGestureDiagnosticOutput"]
        )
    ]
)
