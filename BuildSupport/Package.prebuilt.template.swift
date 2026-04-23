// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExifToolSPM",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ExifTool",
            targets: [
                "ExifTool"
            ]
        )
    ],
    targets: [
        .binaryTarget(
            name: "CExifToolBridge",
            url: "__CEXIFTOOLBRIDGE_URL__",
            checksum: "__CEXIFTOOLBRIDGE_CHECKSUM__"
        ),
        .target(
            name: "ExifTool",
            dependencies: [
                "CExifToolBridge"
            ],
            path: "Sources/ExifTool",
            resources: [
                .copy("Resources/Perl")
            ]
        ),
        .testTarget(
            name: "ExifToolTests",
            dependencies: [
                "ExifTool"
            ],
            path: "Tests/ExifToolTests"
        )
    ]
)
