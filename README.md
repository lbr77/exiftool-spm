# ExifToolSPM

`ExifToolSPM` builds an embedded `libperl` bridge around `Image::ExifTool` and exposes it as a Swift package for Apple platforms.

## Distribution model

`main` is the source branch for development, CI, and release automation.
`prebuilt` is the binary consumption branch for iOS apps and points `Package.swift` at the latest published XCFramework on GitHub Releases.

For app integration, depend on `prebuilt`:

```swift
.package(
    url: "https://github.com/lbr77/exiftool-spm",
    branch: "prebuilt"
)
```

Latest published release:

- https://github.com/lbr77/exiftool-spm/releases/tag/v13.57-perl-5.40.3

## Repository shape

- `Sources/CExifToolBridge`: Stable C ABI that embeds Perl and calls `Image::ExifTool` in-process.
- `Sources/ExifTool`: Swift API and bundled Perl resources.
- `BuildSupport/`: Templates and generated files used for source builds and prebuilt branch publishing.
- `scripts/`: Source staging, Perl toolchain bootstrap, XCFramework build, release bundle assembly, and prebuilt branch publishing.
- `.github/workflows/`: CI for host validation, scheduled release checks, GitHub Releases, and `prebuilt` branch updates.

## Local validation

```bash
bash scripts/test-local.sh
```

This command stages ExifTool `13.57`, builds a host Perl toolchain, generates `BuildSupport/perl-embed-flags.json`, and runs `swift test`.

## Local artifacts

```bash
bash scripts/build-ios-xcframework.sh
```

Outputs:

- `Artifacts/CExifToolBridge.xcframework`
- `Artifacts/CExifToolBridge.xcframework.zip`
- `Artifacts/ExifToolSPM-local-package.tar.gz`

The local package bundle contains the Swift package manifest, Swift sources, Perl resources, and the built XCFramework. Unpack it anywhere and add it to Xcode as a local package.

## Release automation

The `release` workflow supports three paths:

- Manual dispatch with explicit `exiftool-version` and `perl-version`
- Tag-triggered publishing for `v*`
- Daily scheduled checks against `https://exiftool.org/ver.txt`

The scheduled job compares the upstream ExifTool version with the latest GitHub Release tag and starts a new build only when a newer upstream version is available.

Successful release runs publish:

- `CExifToolBridge.xcframework.zip` to GitHub Releases
- `ExifToolSPM-local-package.tar.gz` to GitHub Releases
- An updated `prebuilt` branch with a remote `binaryTarget` checksum
