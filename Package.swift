// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HerdrBar",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "HerdrBar",
            path: "Sources/HerdrBar",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
