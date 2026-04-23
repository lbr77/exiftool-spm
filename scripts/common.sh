#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build"
CACHE_DIR="${BUILD_DIR}/cache"

mkdir -p "${BUILD_DIR}" "${CACHE_DIR}"

download_if_missing() {
  local url="$1"
  local destination="$2"

  if [[ -f "${destination}" ]]; then
    return 0
  fi

  curl --fail --location --silent --show-error "${url}" --output "${destination}"
}

extract_tarball() {
  local archive_path="$1"
  local destination="$2"

  rm -rf "${destination}"
  mkdir -p "${destination}"
  tar -xzf "${archive_path}" -C "${destination}" --strip-components=1
}

host_jobs() {
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
    return 0
  fi

  getconf _NPROCESSORS_ONLN
}

patch_perl_cross_for_darwin() {
  local source_root="$1"
  local file

  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  while IFS= read -r file; do
    perl -0pi -e '
      s/sed -re /sed -Ee /g;
      s/sed -r /sed -E /g;
      s/\\s\+/[[:space:]]+/g;
      s/\\s\*/[[:space:]]*/g;
      s/\\s\$/[[:space:]]\$/g;
      s/\\s/[[:space:]]/g;
    ' "${file}"
  done < <(find "${source_root}" \( -name 'Makefile' -o -name '*.sh' \) -type f)

  perl -0pi -e "s/tryhints 'hint' \"\\\$h\"/tryhints \"\\\$h\"/g" \
    "${source_root}/cnf/configure_hint.sh"

  perl -0pi -e '
    s@mstart "Guessing byte order"\nif not hinted '\''byteorder'\''; then\n.*?\nfi\n\n# Mantissa bits,@mstart "Guessing byte order"\nif not hinted '\''byteorder'\''; then\n\tdefine byteorder '\''12345678'\''\n\tresult '\''12345678'\''\nfi\n\n# Mantissa bits,@s;
  ' "${source_root}/cnf/configure_type_sel.sh"
}
