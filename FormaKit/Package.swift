// swift-tools-version: 5.10
import PackageDescription

// FormaKit holds the app's pure, platform-independent logic: unit conversion,
// trend smoothing, strength estimates, nutrition math, schedules, reviews and
// reminder planning. Keeping it free of UI and Apple-only frameworks makes the
// calculations fast to test (including on Linux CI) and easy to reason about.
let package = Package(
    name: "FormaKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FormaKit", targets: ["FormaKit"])
    ],
    targets: [
        .target(name: "FormaKit"),
        .testTarget(name: "FormaKitTests", dependencies: ["FormaKit"])
    ]
)
