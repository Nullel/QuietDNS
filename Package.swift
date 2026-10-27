// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuietDNS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuietDNS", targets: ["QuietDNSApp"]),
        .executable(name: "quietdns-helper", targets: ["QuietDNSHelper"])
    ],
    targets: [
        .target(name: "QuietDNSCore", linkerSettings: [.linkedFramework("SystemConfiguration")]),
        .executableTarget(name: "QuietDNSHelper", dependencies: ["QuietDNSCore"]),
        .executableTarget(name: "QuietDNSApp", dependencies: ["QuietDNSCore"]),
        .testTarget(name: "QuietDNSCoreTests", dependencies: ["QuietDNSCore"])
    ],
    swiftLanguageModes: [.v5]
)
