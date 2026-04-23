# ExifToolSPM

`prebuilt` is the binary distribution branch for `ExifToolSPM`.
It keeps the Swift wrapper and bundled Perl resources in this repository, and downloads the embedded bridge as a prebuilt XCFramework from GitHub Releases.

## Usage

```swift
.package(
    url: "https://github.com/lbr77/exiftool-spm",
    branch: "prebuilt"
)
```

Then depend on `ExifTool` from your target.

## Current binary

- Release tag: `v13.57-perl-5.40.3`
- XCFramework: `https://github.com/lbr77/exiftool-spm/releases/download/v13.57-perl-5.40.3/CExifToolBridge.xcframework.zip`
- Source commit: `e52e38c25191e8cebdbcbe9ac7af8dc7a9d0536a`

## Platform support

- iOS 15+
- iOS Simulator on Apple Silicon and Intel
