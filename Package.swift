// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Pomolet",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pomolet", targets: ["Pomolet"])],
    targets: [.executableTarget(name: "Pomolet", path: ".", exclude: ["Tools", "Tests", "Brand", "docs", "dist", "LICENSE", "README.md", "README.zh-CN.md", "Info.plist", "build.sh", "test.sh"], sources: ["Sources"], resources: [.copy("Resources")])]
)
