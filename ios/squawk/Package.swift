// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "squawk",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "squawk", targets: ["squawk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "squawk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
