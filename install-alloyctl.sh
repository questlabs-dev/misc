#!/usr/bin/env bash
# alloyctl installer — downloads the latest (or specified) release from the
# public distribution repo. Source lives in a private repo; release.yaml
# publishes the compiled binaries and checksums.txt to questlabs-dev/misc
# under tags named alloyctl-vX.Y.Z.
#
# Usage:
#   curl -sSfL https://raw.githubusercontent.com/questlabs-dev/misc/main/install-alloyctl.sh | bash
#   curl -sSfL ... | bash -s -- --version v1.2.0
#   curl -sSfL ... | bash -s -- --dir /usr/local/bin
set -euo pipefail

REPO="questlabs-dev/misc"
TAG_PREFIX="alloyctl-"
INSTALL_DIR="${HOME}/.local/bin"
VERSION=""

usage() {
  echo "Usage: install.sh [--version VERSION] [--dir DIR]"
  echo ""
  echo "  --version VERSION   Install a specific version (e.g. v1.2.0). Default: latest."
  echo "  --dir DIR           Install directory. Default: ~/.local/bin"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --dir)     INSTALL_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)         echo "Unknown option: $1"; usage ;;
  esac
done

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  mingw*|msys*|cygwin*) OS="windows" ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# The dist repo hosts other files too, so "releases/latest" may not be an
# alloyctl release. Releases are listed newest first; take the first
# alloyctl-v* tag.
if [ -z "$VERSION" ]; then
  echo "Fetching latest release..."
  VERSION="$(curl -sSf "https://api.github.com/repos/${REPO}/releases?per_page=100" \
    | grep -o '"tag_name": *"[^"]*"' \
    | sed -E 's/.*"([^"]+)"$/\1/' \
    | grep "^${TAG_PREFIX}v" \
    | head -n1 \
    | sed "s/^${TAG_PREFIX}//" || true)"
  if [ -z "$VERSION" ]; then
    echo "Error: could not determine latest version. Pass --version explicitly." >&2
    exit 1
  fi
fi
VERSION="${VERSION#"${TAG_PREFIX}"}"
TAG="${TAG_PREFIX}${VERSION}"

EXT=""
if [ "$OS" = "windows" ]; then EXT=".exe"; fi

BINARY="alloyctl-${OS}-${ARCH}${EXT}"
BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"
URL="${BASE_URL}/${BINARY}"

echo "Installing alloyctl ${VERSION} (${OS}/${ARCH})..."
echo "  From: ${URL}"
echo "  To:   ${INSTALL_DIR}/alloyctl${EXT}"

mkdir -p "$INSTALL_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HTTP_CODE=$(curl -sSL -o "${TMP}/${BINARY}" -w "%{http_code}" "$URL")
if [ "$HTTP_CODE" != "200" ]; then
  echo "Error: download failed (HTTP ${HTTP_CODE}). Check the version exists at:" >&2
  echo "  https://github.com/${REPO}/releases" >&2
  exit 1
fi

# Verify against the release's checksums.txt.
if curl -sSfL -o "${TMP}/checksums.txt" "${BASE_URL}/checksums.txt"; then
  EXPECTED="$(grep " ${BINARY}\$" "${TMP}/checksums.txt" | awk '{print $1}')"
  if [ -z "$EXPECTED" ]; then
    echo "Error: ${BINARY} not listed in checksums.txt" >&2
    exit 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "${TMP}/${BINARY}" | awk '{print $1}')"
  else
    ACTUAL="$(shasum -a 256 "${TMP}/${BINARY}" | awk '{print $1}')"
  fi
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Error: checksum mismatch for ${BINARY}" >&2
    echo "  expected ${EXPECTED}" >&2
    echo "  got      ${ACTUAL}" >&2
    exit 1
  fi
  echo "  Checksum OK"
else
  echo "Error: could not download checksums.txt for ${TAG}" >&2
  exit 1
fi

mv "${TMP}/${BINARY}" "${INSTALL_DIR}/alloyctl${EXT}"
chmod +x "${INSTALL_DIR}/alloyctl${EXT}"

echo ""
echo "✓ alloyctl ${VERSION} installed to ${INSTALL_DIR}/alloyctl${EXT}"
echo ""

# Check if install dir is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo "⚠ ${INSTALL_DIR} is not in your PATH. Add it with:"
  echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
  echo ""
fi

"${INSTALL_DIR}/alloyctl${EXT}" version
