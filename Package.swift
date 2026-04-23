// swift-tools-version: 6.0

import Foundation
import PackageDescription

struct PerlBuildSettings: Decodable {
    let cFlags: [String]
    let linkerFlags: [String]
}

let binaryArtifactPath = "Artifacts/CExifToolBridge.xcframework"
let buildSettingsPath = "BuildSupport/perl-embed-flags.json"
let useBinaryArtifact = FileManager.default.fileExists(atPath: binaryArtifactPath)

func loadPerlBuildSettings() -> PerlBuildSettings? {
    guard FileManager.default.fileExists(atPath: buildSettingsPath) else {
        return nil
    }

    let data = try! Data(contentsOf: URL(fileURLWithPath: buildSettingsPath))
    return try! JSONDecoder().decode(PerlBuildSettings.self, from: data)
}

let perlBuildSettings = loadPerlBuildSettings()

var targets: [Target] = []

if useBinaryArtifact {
    targets.append(
        .binaryTarget(
            name: "CExifToolBridge",
            path: binaryArtifactPath
        )
    )
} else {
    guard let perlBuildSettings else {
        fatalError(
            """
            Missing \(buildSettingsPath).
            Run `bash scripts/test-local.sh` or `bash scripts/build-host-perl.sh` first.
            """
        )
    }

    targets.append(
        .target(
            name: "CExifToolBridge",
            path: "Sources/CExifToolBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(perlBuildSettings.cFlags)
            ],
            linkerSettings: [
                .unsafeFlags(perlBuildSettings.linkerFlags)
            ]
        )
    )
}

targets.append(
    .target(
        name: "ExifTool",
        dependencies: [
            "CExifToolBridge"
        ],
        path: "Sources/ExifTool",
        resources: [
            .copy("Resources/Perl")
        ]
    )
)

targets.append(
    .testTarget(
        name: "ExifToolTests",
        dependencies: [
            "ExifTool"
        ],
        path: "Tests/ExifToolTests"
    )
)

let package = Package(
    name: "ExifToolSPM",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ExifTool",
            targets: [
                "ExifTool"
            ]
        )
    ],
    targets: targets
)
