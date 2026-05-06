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
            url: "https://github.com/lbr77/exiftool-spm/releases/download/v13.58-perl-5.40.3/CExifToolBridge.xcframework.zip",
            checksum: "1b3dd886607a5dfbfccc69f816a41fcbf69e6edb0ef1b8b47d82ac83b84510b9"
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
