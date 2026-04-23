#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${ROOT_DIR}/scripts/build-host-perl.sh"
bash "${ROOT_DIR}/scripts/stage-exiftool.sh"

swift test --package-path "${ROOT_DIR}"
