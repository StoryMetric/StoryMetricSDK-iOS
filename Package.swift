// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StoryMetric",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "StoryMetric", targets: ["StoryMetric"]),
    ],
    targets: [
        .target(
            name: "StoryMetric",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(name: "StoryMetricTests", dependencies: ["StoryMetric"]),
    ]
)
