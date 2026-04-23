#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

RELEASE_TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
CEXIFTOOLBRIDGE_URL="${CEXIFTOOLBRIDGE_URL:?CEXIFTOOLBRIDGE_URL is required}"
CEXIFTOOLBRIDGE_CHECKSUM="${CEXIFTOOLBRIDGE_CHECKSUM:?CEXIFTOOLBRIDGE_CHECKSUM is required}"
PREBUILT_BRANCH="${PREBUILT_BRANCH:-prebuilt}"
SOURCE_REF="${SOURCE_REF:-$(git -C "${ROOT_DIR}" rev-parse HEAD)}"
SOURCE_COMMIT="$(git -C "${ROOT_DIR}" rev-parse "${SOURCE_REF}")"
WORKTREE_DIR="${BUILD_DIR}/prebuilt-branch"
PACKAGE_TEMPLATE="${ROOT_DIR}/BuildSupport/Package.prebuilt.template.swift"
README_TEMPLATE="${ROOT_DIR}/BuildSupport/README.prebuilt.template.md"

render_template() {
  local input_path="$1"
  local output_path="$2"

  RELEASE_TAG="${RELEASE_TAG}" \
  CEXIFTOOLBRIDGE_URL="${CEXIFTOOLBRIDGE_URL}" \
  CEXIFTOOLBRIDGE_CHECKSUM="${CEXIFTOOLBRIDGE_CHECKSUM}" \
  SOURCE_COMMIT="${SOURCE_COMMIT}" \
  perl -0pe '
    s/__RELEASE_TAG__/$ENV{RELEASE_TAG}/g;
    s/__CEXIFTOOLBRIDGE_URL__/$ENV{CEXIFTOOLBRIDGE_URL}/g;
    s/__CEXIFTOOLBRIDGE_CHECKSUM__/$ENV{CEXIFTOOLBRIDGE_CHECKSUM}/g;
    s/__SOURCE_COMMIT__/$ENV{SOURCE_COMMIT}/g;
  ' "${input_path}" > "${output_path}"
}

git -C "${ROOT_DIR}" fetch origin "${PREBUILT_BRANCH}:${PREBUILT_BRANCH}" >/dev/null 2>&1 || true

rm -rf "${WORKTREE_DIR}"

if git -C "${ROOT_DIR}" show-ref --verify --quiet "refs/heads/${PREBUILT_BRANCH}"; then
  git -C "${ROOT_DIR}" worktree add "${WORKTREE_DIR}" "${PREBUILT_BRANCH}" >/dev/null
else
  git -C "${ROOT_DIR}" worktree add -b "${PREBUILT_BRANCH}" "${WORKTREE_DIR}" "${SOURCE_REF}" >/dev/null
fi

cleanup() {
  git -C "${ROOT_DIR}" worktree remove --force "${WORKTREE_DIR}" >/dev/null 2>&1 || true
}

trap cleanup EXIT

find "${WORKTREE_DIR}" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
git -C "${ROOT_DIR}" archive "${SOURCE_REF}" | tar -x -C "${WORKTREE_DIR}"

render_template "${PACKAGE_TEMPLATE}" "${WORKTREE_DIR}/Package.swift"
render_template "${README_TEMPLATE}" "${WORKTREE_DIR}/README.md"

pushd "${WORKTREE_DIR}" >/dev/null

git add -A

if git diff --cached --quiet; then
  exit 0
fi

git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"

git commit -m "Update prebuilt package for ${RELEASE_TAG}" >/dev/null
git push origin "HEAD:${PREBUILT_BRANCH}" >/dev/null

popd >/dev/null
