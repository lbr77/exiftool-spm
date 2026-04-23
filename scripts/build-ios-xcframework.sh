#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PERL_VERSION="${PERL_VERSION:-5.40.3}"
PERL_CROSS_VERSION="${PERL_CROSS_VERSION:-1.6.4}"
IOS_MIN_VERSION="${IOS_MIN_VERSION:-15.0}"
PERL_ARCHIVE="${CACHE_DIR}/perl-${PERL_VERSION}.tar.gz"
PERL_CROSS_ARCHIVE="${CACHE_DIR}/perl-cross-${PERL_CROSS_VERSION}.tar.gz"
IOS_BUILD_ROOT="${BUILD_DIR}/toolchains/ios"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts"
HEADERS_DIR="${BUILD_DIR}/xcframework-headers"
READELF_COMPAT="${ROOT_DIR}/scripts/readelf-compat.sh"
LLVM_OBJDUMP="$(xcrun -f llvm-objdump)"
LIPO_TOOL="$(xcrun -f lipo)"
JOBS="$(host_jobs)"

download_if_missing \
  "https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz" \
  "${PERL_ARCHIVE}"

download_if_missing \
  "https://github.com/arsv/perl-cross/archive/refs/tags/${PERL_CROSS_VERSION}.tar.gz" \
  "${PERL_CROSS_ARCHIVE}"

bash "${ROOT_DIR}/scripts/stage-exiftool.sh"

rm -rf "${HEADERS_DIR}"
mkdir -p "${HEADERS_DIR}"
cp "${ROOT_DIR}/Sources/CExifToolBridge/include/exiftool_bridge.h" "${HEADERS_DIR}/exiftool_bridge.h"
cat > "${HEADERS_DIR}/module.modulemap" <<'EOF'
module CExifToolBridge {
  header "exiftool_bridge.h"
  export *
}
EOF

build_slice() {
  local sdk="$1"
  local arch="$2"
  local target="$3"
  local platform_flag="$4"
  local slice_name="$5"
  local sdk_root
  local compiler
  local build_dir
  local compiler_flags
  local source_dir
  local perl_core_dir
  local libperl_path
  local ar_tool
  local nm_tool
  local ranlib_tool

  sdk_root="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  compiler="$(xcrun --sdk "${sdk}" -f clang)"
  build_dir="${IOS_BUILD_ROOT}/${slice_name}"
  source_dir="${build_dir}/source"
  compiler_flags="-arch ${arch} -isysroot ${sdk_root} ${platform_flag}${IOS_MIN_VERSION}"
  ar_tool="$(xcrun --sdk "${sdk}" -f ar)"
  nm_tool="$(xcrun --sdk "${sdk}" -f nm)"
  ranlib_tool="$(xcrun --sdk "${sdk}" -f ranlib)"

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
    CFLAGS="${compiler_flags}" \
    CPPFLAGS="${compiler_flags}" \
    LDFLAGS="${compiler_flags}" \
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
    -arch "${arch}" \
    -isysroot "${sdk_root}" \
    "${platform_flag}${IOS_MIN_VERSION}" \
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

build_slice "iphoneos" "arm64" "arm64-apple-ios" "-miphoneos-version-min=" "ios-arm64"
build_slice "iphonesimulator" "arm64" "arm64-apple-iossimulator" "-mios-simulator-version-min=" "ios-sim-arm64"
build_slice "iphonesimulator" "x86_64" "x86_64-apple-iossimulator" "-mios-simulator-version-min=" "ios-sim-x86_64"

rm -rf "${IOS_BUILD_ROOT}/ios-simulator-universal"
mkdir -p "${IOS_BUILD_ROOT}/ios-simulator-universal"
"${LIPO_TOOL}" -create \
  "${IOS_BUILD_ROOT}/ios-sim-arm64/libCExifToolBridge.a" \
  "${IOS_BUILD_ROOT}/ios-sim-x86_64/libCExifToolBridge.a" \
  -output "${IOS_BUILD_ROOT}/ios-simulator-universal/libCExifToolBridge.a"

rm -rf "${ARTIFACTS_DIR}/CExifToolBridge.xcframework"
mkdir -p "${ARTIFACTS_DIR}"

xcodebuild -create-xcframework \
  -library "${IOS_BUILD_ROOT}/ios-arm64/libCExifToolBridge.a" -headers "${HEADERS_DIR}" \
  -library "${IOS_BUILD_ROOT}/ios-simulator-universal/libCExifToolBridge.a" -headers "${HEADERS_DIR}" \
  -output "${ARTIFACTS_DIR}/CExifToolBridge.xcframework"

pushd "${ARTIFACTS_DIR}" >/dev/null
rm -f CExifToolBridge.xcframework.zip
ditto -c -k --sequesterRsrc --keepParent CExifToolBridge.xcframework CExifToolBridge.xcframework.zip
popd >/dev/null

bash "${ROOT_DIR}/scripts/assemble-local-package.sh"
