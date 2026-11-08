// swift-tools-version:5.9
import PackageDescription

// libgphoto2 comes from Homebrew; there is no pkg-config on this machine, so the
// include and library paths are given explicitly.
let homebrewInclude: [SwiftSetting] = [.unsafeFlags(["-Xcc", "-I/opt/homebrew/include"])]
let homebrewLib: [LinkerSetting] = [.unsafeFlags(["-L/opt/homebrew/lib"])]

let package = Package(
    name: "LensControl",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CGPhoto2",
            path: "Sources/CGPhoto2"
        ),
        .executableTarget(
            name: "LensControl",
            dependencies: ["CGPhoto2"],
            path: "Sources/LensControl",
            swiftSettings: homebrewInclude,
            linkerSettings: homebrewLib
        ),
        .testTarget(
            name: "LensControlTests",
            dependencies: ["LensControl"],
            path: "Tests/LensControlTests",
            swiftSettings: homebrewInclude,
            linkerSettings: homebrewLib
        ),
    ]
)
