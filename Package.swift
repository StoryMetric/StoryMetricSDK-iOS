// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "StoryMetric",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "StoryMetric", targets: ["StoryMetric"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .macro(
            name: "StoryMetricMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "StoryMetric",
            dependencies: ["StoryMetricMacros"],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(name: "StoryMetricTests", dependencies: ["StoryMetric"]),
        .testTarget(
            name: "StoryMetricMacroTests",
            dependencies: [
                "StoryMetricMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
