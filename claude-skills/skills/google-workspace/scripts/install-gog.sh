#!/usr/bin/env bash
# install-gog.sh — install the `gog` CLI (openclaw/gogcli) from a GitHub
# release, for hosts without Homebrew (typically Linux).
#
#   bash install-gog.sh [--version X.Y.Z] [--dir DIR]
#
# Downloads gogcli_<ver>_<os>_<arch>.tar.gz, verifies it against the release's
# checksums.txt, and installs `gog` into DIR (default: ~/.local/bin).
#
# Part of the BSG google-workspace skill.
set -euo pipefail

REPO="openclaw/gogcli"
VERSION=""
DIR="${GOG_INSTALL_DIR:-$HOME/.local/bin}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2#v}"; shift 2 ;;
    --dir)     DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "error: unknown arg $1" >&2; exit 2 ;;
  esac
done

case "$(uname -s)" in
  Linux)  os=linux ;;
  Darwin) os=darwin ;;
  *) echo "error: unsupported OS $(uname -s) — see https://github.com/$REPO#install" >&2; exit 2 ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "error: unsupported arch $(uname -m)" >&2; exit 2 ;;
esac

for c in curl tar sha256sum; do
  command -v "$c" >/dev/null 2>&1 || { [[ $c == sha256sum ]] && command -v shasum >/dev/null 2>&1; } \
    || { echo "error: $c is required" >&2; exit 2; }
done
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }

if [[ -z "$VERSION" ]]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -nE 's/.*"tag_name": *"v?([^"]+)".*/\1/p' | head -1)
  [[ -n "$VERSION" ]] || { echo "error: could not resolve latest release" >&2; exit 1; }
fi

asset="gogcli_${VERSION}_${os}_${arch}.tar.gz"
base="https://github.com/$REPO/releases/download/v${VERSION}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

echo "▸ downloading $asset"
curl -fsSL -o "$tmp/$asset" "$base/$asset"
curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"

want=$(awk -v a="$asset" '$2==a || $2=="*"a {print $1}' "$tmp/checksums.txt")
got=$(sha "$tmp/$asset" | awk '{print $1}')
[[ -n "$want" && "$want" == "$got" ]] || { echo "error: checksum mismatch for $asset" >&2; exit 1; }

tar -xzf "$tmp/$asset" -C "$tmp"
bin=$(find "$tmp" -type f -name gog | head -1)
[[ -n "$bin" ]] || { echo "error: no gog binary in archive" >&2; exit 1; }
mkdir -p "$DIR"
install -m 0755 "$bin" "$DIR/gog"
echo "✓ installed $("$DIR/gog" --version | head -1) → $DIR/gog"
case ":$PATH:" in *":$DIR:"*) ;; *) echo "⚠ $DIR is not on PATH — add: export PATH=\"$DIR:\$PATH\"" ;; esac
