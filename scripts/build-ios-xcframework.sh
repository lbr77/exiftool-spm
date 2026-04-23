#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PERL_VERSION="${PERL_VERSION:-5.40.3}"
PERL_CROSS_VERSION="${PERL_CROSS_VERSION:-1.6.4}"
IOS_MIN_VERSION="${IOS_MIN_VERSION:-15.0}"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-13.0}"
MAC_CATALYST_MIN_VERSION="${MAC_CATALYST_MIN_VERSION:-15.0}"
PERL_ARCHIVE="${CACHE_DIR}/perl-${PERL_VERSION}.tar.gz"
PERL_CROSS_ARCHIVE="${CACHE_DIR}/perl-cross-${PERL_CROSS_VERSION}.tar.gz"
IOS_BUILD_ROOT="${BUILD_DIR}/toolchains/ios"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts"
HEADERS_DIR="${BUILD_DIR}/xcframework-headers"
READELF_COMPAT="${ROOT_DIR}/scripts/readelf-compat.sh"
LLVM_OBJDUMP="$(xcrun -f llvm-objdump)"
LIPO_TOOL="$(xcrun -f lipo)"
JOBS="$(host_jobs)"
HOST_ARCH="$(uname -m)"
HOST_PERL_PREFIX="${BUILD_DIR}/toolchains/perl-host-${PERL_VERSION}"
HOST_PERL_CORE_DIR="${HOST_PERL_PREFIX}/lib/${PERL_VERSION}/darwin-2level/CORE"

download_if_missing \
  "https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz" \
  "${PERL_ARCHIVE}"

download_if_missing \
  "https://github.com/arsv/perl-cross/archive/refs/tags/${PERL_CROSS_VERSION}.tar.gz" \
  "${PERL_CROSS_ARCHIVE}"

bash "${ROOT_DIR}/scripts/stage-exiftool.sh"
bash "${ROOT_DIR}/scripts/build-host-perl.sh"

rm -rf "${HEADERS_DIR}"
mkdir -p "${HEADERS_DIR}"
cp "${ROOT_DIR}/Sources/CExifToolBridge/include/exiftool_bridge.h" "${HEADERS_DIR}/exiftool_bridge.h"
cat > "${HEADERS_DIR}/module.modulemap" <<'EOF'
module CExifToolBridge {
  header "exiftool_bridge.h"
  export *
}
EOF

build_cross_slice() {
  local sdk="$1"
  local arch="$2"
  local target="$3"
  local platform_kind="$4"
  local slice_name="$5"
  local sdk_root
  local compiler
  local build_dir
  local compiler_flags_string
  local source_dir
  local perl_core_dir
  local libperl_path
  local ar_tool
  local nm_tool
  local ranlib_tool
  local -a compiler_flags

  sdk_root="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  compiler="$(xcrun --sdk "${sdk}" -f clang)"
  build_dir="${IOS_BUILD_ROOT}/${slice_name}"
  source_dir="${build_dir}/source"
  ar_tool="$(xcrun --sdk "${sdk}" -f ar)"
  nm_tool="$(xcrun --sdk "${sdk}" -f nm)"
  ranlib_tool="$(xcrun --sdk "${sdk}" -f ranlib)"

  case "${platform_kind}" in
    ios)
      compiler_flags=(
        -arch "${arch}"
        -isysroot "${sdk_root}"
        "-miphoneos-version-min=${IOS_MIN_VERSION}"
      )
      ;;
    ios-simulator)
      compiler_flags=(
        -arch "${arch}"
        -isysroot "${sdk_root}"
        "-mios-simulator-version-min=${IOS_MIN_VERSION}"
      )
      ;;
    mac-catalyst)
      # Mac Catalyst slices are built from the macOS SDK with an iOS macabi target triple.
      compiler_flags=(
        -target "${arch}-apple-ios${MAC_CATALYST_MIN_VERSION}-macabi"
        -isysroot "${sdk_root}"
      )
      ;;
    *)
      echo "Unsupported platform kind: ${platform_kind}" >&2
      exit 1
      ;;
  esac

  compiler_flags_string="${compiler_flags[*]}"

  extract_tarball "${PERL_ARCHIVE}" "${source_dir}"
  tar -xzf "${PERL_CROSS_ARCHIVE}" -C "${source_dir}" --strip-components=1
  patch_perl_cross_for_darwin "${source_dir}"
  cat > "${source_dir}/cnf/hints/exiftool_apple" <<'EOF'
d_nanosleep='define'
d_clock_nanosleep='define'
usedl='undef'
EOF

  pushd "${source_dir}" >/dev/null

  env \
    HOSTREADELF="${READELF_COMPAT}" \
    READELF="${READELF_COMPAT}" \
    HOSTOBJDUMP="${LLVM_OBJDUMP}" \
    OBJDUMP="${LLVM_OBJDUMP}" \
    CC="${compiler}" \
    CPP="${compiler} -E" \
    AR="${ar_tool}" \
    NM="${nm_tool}" \
    RANLIB="${ranlib_tool}" \
    CFLAGS="${compiler_flags_string}" \
    CPPFLAGS="${compiler_flags_string}" \
    LDFLAGS="${compiler_flags_string}" \
    ./configure \
    --target="${target}" \
    --host-hints=exiftool_apple \
    --hints=exiftool_apple \
    --prefix="${build_dir}/prefix" \
    --sysroot="${sdk_root}" \
    -Duseshrplib=false \
    -Dman1dir=none \
    -Dman3dir=none

  make -j"${JOBS}" libperl.a
  popd >/dev/null

  perl_core_dir="${source_dir}"
  libperl_path="${source_dir}/libperl.a"

  mkdir -p "${build_dir}/objects"

  xcrun --sdk "${sdk}" clang \
    "${compiler_flags[@]}" \
    -fvisibility=hidden \
    -I"${ROOT_DIR}/Sources/CExifToolBridge/include" \
    -I"${perl_core_dir}" \
    -c "${ROOT_DIR}/Sources/CExifToolBridge/exiftool_bridge.c" \
    -o "${build_dir}/objects/exiftool_bridge.o"

  libtool -static \
    -o "${build_dir}/libCExifToolBridge.a" \
    "${build_dir}/objects/exiftool_bridge.o" \
    "${libperl_path}"
}

build_host_macos_slice() {
  local sdk_root
  local build_dir

  sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
  build_dir="${IOS_BUILD_ROOT}/macos-${HOST_ARCH}"

  mkdir -p "${build_dir}/objects"

  xcrun --sdk macosx clang \
    -arch "${HOST_ARCH}" \
    -isysroot "${sdk_root}" \
    "-mmacosx-version-min=${MACOS_MIN_VERSION}" \
    -fvisibility=hidden \
    -I"${ROOT_DIR}/Sources/CExifToolBridge/include" \
    -I"${HOST_PERL_CORE_DIR}" \
    -c "${ROOT_DIR}/Sources/CExifToolBridge/exiftool_bridge.c" \
    -o "${build_dir}/objects/exiftool_bridge.o"

  libtool -static \
    -o "${build_dir}/libCExifToolBridge.a" \
    "${build_dir}/objects/exiftool_bridge.o" \
    "${HOST_PERL_CORE_DIR}/libperl.a"
}

build_host_macos_slice
build_cross_slice "iphoneos" "arm64" "arm64-apple-ios" "ios" "ios-arm64"
build_cross_slice "iphonesimulator" "arm64" "arm64-apple-iossimulator" "ios-simulator" "ios-sim-arm64"
build_cross_slice "iphonesimulator" "x86_64" "x86_64-apple-iossimulator" "ios-simulator" "ios-sim-x86_64"
build_cross_slice "macosx" "arm64" "arm64-apple-darwin" "mac-catalyst" "catalyst-arm64"
build_cross_slice "macosx" "x86_64" "x86_64-apple-darwin" "mac-catalyst" "catalyst-x86_64"

rm -rf "${IOS_BUILD_ROOT}/ios-simulator-universal"
mkdir -p "${IOS_BUILD_ROOT}/ios-simulator-universal"
"${LIPO_TOOL}" -create \
  "${IOS_BUILD_ROOT}/ios-sim-arm64/libCExifToolBridge.a" \
  "${IOS_BUILD_ROOT}/ios-sim-x86_64/libCExifToolBridge.a" \
  -output "${IOS_BUILD_ROOT}/ios-simulator-universal/libCExifToolBridge.a"

rm -rf "${IOS_BUILD_ROOT}/catalyst-universal"
mkdir -p "${IOS_BUILD_ROOT}/catalyst-universal"
"${LIPO_TOOL}" -create \
  "${IOS_BUILD_ROOT}/catalyst-arm64/libCExifToolBridge.a" \
  "${IOS_BUILD_ROOT}/catalyst-x86_64/libCExifToolBridge.a" \
  -output "${IOS_BUILD_ROOT}/catalyst-universal/libCExifToolBridge.a"

rm -rf "${ARTIFACTS_DIR}/CExifToolBridge.xcframework"
mkdir -p "${ARTIFACTS_DIR}"

xcodebuild -create-xcframework \
  -library "${IOS_BUILD_ROOT}/macos-${HOST_ARCH}/libCExifToolBridge.a" -headers "${HEADERS_DIR}" \
  -library "${IOS_BUILD_ROOT}/ios-arm64/libCExifToolBridge.a" -headers "${HEADERS_DIR}" \
  -library "${IOS_BUILD_ROOT}/ios-simulator-universal/libCExifToolBridge.a" -headers "${HEADERS_DIR}" \
  -library "${IOS_BUILD_ROOT}/catalyst-universal/libCExifToolBridge.a" -headers "${HEADERS_DIR}" \
  -output "${ARTIFACTS_DIR}/CExifToolBridge.xcframework"

pushd "${ARTIFACTS_DIR}" >/dev/null
rm -f CExifToolBridge.xcframework.zip
ditto -c -k --sequesterRsrc --keepParent CExifToolBridge.xcframework CExifToolBridge.xcframework.zip
popd >/dev/null

bash "${ROOT_DIR}/scripts/assemble-local-package.sh"
