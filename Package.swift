// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JaagteRahoCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "JaagteRahoCore", targets: ["JaagteRahoCore"])],
    targets: [
        .target(name: "JaagteRahoCore", path: "iOS/JaagteRaho/Core"),
        .testTarget(name: "JaagteRahoCoreTests", dependencies: ["JaagteRahoCore"],
                    path: "Tests/JaagteRahoCoreTests")
    ]
)
