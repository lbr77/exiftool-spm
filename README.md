# ExifToolSPM

`ExifToolSPM` builds an embedded `libperl` bridge around `Image::ExifTool` and exposes it as a Swift package for Apple platforms.

## Repository shape

- `Sources/CExifToolBridge`: Stable C ABI that embeds Perl and calls `Image::ExifTool` in-process.
- `Sources/ExifTool`: Swift API and bundled Perl resources.
- `scripts/`: Source staging, Perl toolchain bootstrap, iOS XCFramework build, and release bundle assembly.
- `.github/workflows/`: CI for host validation and release artifacts.

## Local validation

```bash
bash scripts/test-local.sh
```

This command stages ExifTool `13.57`, builds a host Perl toolchain, generates `BuildSupport/perl-embed-flags.json`, and runs `swift test`.

## iOS artifact build

```bash
bash scripts/build-ios-xcframework.sh
```

Outputs:

- `Artifacts/CExifToolBridge.xcframework`
- `Artifacts/CExifToolBridge.xcframework.zip`
- `Artifacts/ExifToolSPM-local-package.tar.gz`

The local package bundle contains the Swift package manifest, Swift sources, Perl resources, and the built XCFramework. Unpack it anywhere and add it to Xcode as a local package.
