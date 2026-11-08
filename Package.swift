// swift-tools-version:5.9
import PackageDescription

// libgphoto2 comes from Homebrew; there is no pkg-config on this machine, so the
// include and library paths are given explicitly.
let homebrewInclude: [SwiftSetting] = [.unsafeFlags(["-Xcc", "-I/opt/homebrew/include"])]
let homebrewLib: [LinkerSetting] = [.unsafeFlags(["-L/opt/homebrew/lib"])]

let package = Package(
    name: "LensBar",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CGPhoto2",
            path: "Sources/CGPhoto2"
        ),
        .executableTarget(
            name: "LensBar",
            dependencies: ["CGPhoto2"],
            path: "Sources/LensBar",
            swiftSettings: homebrewInclude,
            linkerSettings: homebrewLib
        ),
        .testTarget(
            name: "LensBarTests",
            dependencies: ["LensBar"],
            path: "Tests/LensBarTests",
            swiftSettings: homebrewInclude,
            linkerSettings: homebrewLib
        ),
    ]
)
