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

- Release tag: `__RELEASE_TAG__`
- XCFramework: `__CEXIFTOOLBRIDGE_URL__`
- Source commit: `__SOURCE_COMMIT__`

## Platform support

- iOS 15+
- iOS Simulator on Apple Silicon and Intel
