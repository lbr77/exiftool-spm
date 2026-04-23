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
            checksum: "416e1cc3223aef58880bd30de0544a6cbfca79b58ac7158f41d9cc5a50e820eb"
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
