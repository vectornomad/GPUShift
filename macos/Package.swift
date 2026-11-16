// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "GPUShift", platforms: [.macOS(.v13)], products: [.executable(name: "GPUShift", targets: ["GPUShift"])], targets: [.executableTarget(name: "GPUShift", path: "Sources/GPUShift")])
