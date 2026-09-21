// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "shiftpick",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ShiftPick", targets: ["ShiftPickApp"]),
    ],
    targets: [
        .target(name: "ShiftPickCore"),
        .target(name: "ShiftPickPlatform", dependencies: ["ShiftPickCore"]),
        .executableTarget(name: "ShiftPickApp", dependencies: ["ShiftPickCore", "ShiftPickPlatform"]),
        // The Accessibility probe. It is never put in the bundle: scripts/make-app.sh copies one
        // executable, and this is not it. A command-line tool inherits the Accessibility grant of the
        // terminal that starts it, which is the only way to read Finder's real hierarchy while
        // developing.
        .executableTarget(name: "axdump", dependencies: ["ShiftPickCore", "ShiftPickPlatform"],
                          path: "Tools/axdump"),
        .testTarget(name: "ShiftPickCoreTests", dependencies: ["ShiftPickCore"]),
        // ShiftPickCore is declared explicitly: the platform tests build layouts out of Core's own
        // types, and relying on SwiftPM's transitive module search path for that is incidental,
        // not a guarantee.
        .testTarget(name: "ShiftPickPlatformTests",
                    dependencies: ["ShiftPickPlatform", "ShiftPickCore"]),
    ]
)
