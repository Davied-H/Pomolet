// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Pomolet",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pomolet", targets: ["Pomolet"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(name: "Pomolet", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: ".", exclude: ["Tools", "Tests", "Brand", "docs", "dist", "LICENSE", "README.md", "README.zh-CN.md", "Info.plist", "build.sh", "test.sh"], sources: ["Sources"], resources: [.copy("Resources")])]
)
