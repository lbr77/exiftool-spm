#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PACKAGE_ROOT="${BUILD_DIR}/release-package"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts"

rm -rf "${PACKAGE_ROOT}"
mkdir -p "${PACKAGE_ROOT}/Artifacts" "${PACKAGE_ROOT}/Sources" "${PACKAGE_ROOT}/Tests"

cp "${ROOT_DIR}/Package.swift" "${PACKAGE_ROOT}/Package.swift"
cp -R "${ROOT_DIR}/Sources/ExifTool" "${PACKAGE_ROOT}/Sources/ExifTool"
cp -R "${ARTIFACTS_DIR}/CExifToolBridge.xcframework" "${PACKAGE_ROOT}/Artifacts/CExifToolBridge.xcframework"

pushd "${PACKAGE_ROOT}" >/dev/null
tar -czf "${ARTIFACTS_DIR}/ExifToolSPM-local-package.tar.gz" .
popd >/dev/null
