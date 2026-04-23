#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

EXIFTOOL_VERSION="${EXIFTOOL_VERSION:-13.57}"
PERL_VERSION="${PERL_VERSION:-5.40.3}"
EXIFTOOL_ARCHIVE="${EXIFTOOL_ARCHIVE:-${CACHE_DIR}/Image-ExifTool-${EXIFTOOL_VERSION}.tar.gz}"
EXIFTOOL_SOURCE_DIR="${BUILD_DIR}/vendor/exiftool-${EXIFTOOL_VERSION}"
PERL_PREFIX="${BUILD_DIR}/toolchains/perl-host-${PERL_VERSION}"
PERL_VERSION_LIB="${PERL_PREFIX}/lib/${PERL_VERSION}"
RESOURCE_DIR="${ROOT_DIR}/Sources/ExifTool/Resources/Perl"
LOCAL_ARCHIVE="${EXIFTOOL_LOCAL_ARCHIVE:-}"

if [[ -n "${LOCAL_ARCHIVE}" ]]; then
  cp "${LOCAL_ARCHIVE}" "${EXIFTOOL_ARCHIVE}"
else
  download_if_missing \
    "https://exiftool.org/Image-ExifTool-${EXIFTOOL_VERSION}.tar.gz" \
    "${EXIFTOOL_ARCHIVE}"
fi

extract_tarball "${EXIFTOOL_ARCHIVE}" "${EXIFTOOL_SOURCE_DIR}"

if [[ ! -x "${PERL_PREFIX}/bin/perl" ]]; then
  bash "${ROOT_DIR}/scripts/build-host-perl.sh"
fi

rm -rf "${RESOURCE_DIR}/lib"
mkdir -p "${RESOURCE_DIR}/lib/perl5/${PERL_VERSION}"

PERL_CONFIG_PM="$(find_first_file_named "${PERL_VERSION_LIB}" "Config.pm")"
PERL_ARCH_LIB_DIR=""

if [[ -n "${PERL_CONFIG_PM}" ]]; then
  PERL_ARCH_LIB_DIR="$(dirname "${PERL_CONFIG_PM}")"
fi

rsync -a \
  --exclude '*.bundle' \
  --exclude '*.dylib' \
  --exclude '*.so' \
  --exclude '*.a' \
  --exclude '*.bs' \
  --exclude 'CORE' \
  "${PERL_VERSION_LIB}/" \
  "${RESOURCE_DIR}/lib/perl5/${PERL_VERSION}/"

if [[ -n "${PERL_ARCH_LIB_DIR}" && -d "${PERL_ARCH_LIB_DIR}" ]]; then
  rsync -a \
    --exclude '*.bundle' \
    --exclude '*.dylib' \
    --exclude '*.so' \
    --exclude '*.a' \
    --exclude '*.bs' \
    --exclude 'CORE' \
    "${PERL_ARCH_LIB_DIR}/" \
    "${RESOURCE_DIR}/lib/perl5/${PERL_VERSION}/"
fi

rsync -a \
  "${EXIFTOOL_SOURCE_DIR}/lib/" \
  "${RESOURCE_DIR}/lib/"
printf '%s\n' "${EXIFTOOL_VERSION}" > "${RESOURCE_DIR}/VERSION.txt"
