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
            url: "https://github.com/lbr77/exiftool-spm/releases/download/v13.57-perl-5.40.3/CExifToolBridge.xcframework.zip",
            checksum: "7994a7d1f8631e663166701ee4a18fd4ac9eec87410b316fa524721f32707c3a"
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
