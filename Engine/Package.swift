// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VIDLOADPluginEngine",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VIDLOADPluginEngine", targets: ["VIDLOADPluginEngine"])
    ],
    targets: [
        .executableTarget(name: "VIDLOADPluginEngine")
    ],
    swiftLanguageModes: [.v5]
)
