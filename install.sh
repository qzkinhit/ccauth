#!/usr/bin/env sh
# ccauth installer
#   curl -fsSL https://raw.githubusercontent.com/qzkinhit/ccauth/main/install.sh | sh
# Set PREFIX to install somewhere other than ~/.local/bin.
set -eu

REPO="qzkinhit/ccauth"
BRANCH="${CCAUTH_BRANCH:-main}"
PREFIX="${PREFIX:-$HOME/.local/bin}"
URL="https://raw.githubusercontent.com/$REPO/$BRANCH/ccauth"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ccauth: python3 is required but was not found in PATH" >&2
  exit 1
fi

mkdir -p "$PREFIX"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "$TMP"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP" "$URL"
else
  echo "ccauth: need curl or wget to download" >&2
  exit 1
fi

head -n 1 "$TMP" | grep -q python3 || { echo "ccauth: download looks wrong" >&2; exit 1; }

install -m 755 "$TMP" "$PREFIX/ccauth"
echo "Installed $PREFIX/ccauth"

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo "Note: $PREFIX is not in PATH. Add this to your shell profile:"
     echo "  export PATH=\"$PREFIX:\$PATH\"" ;;
esac

"$PREFIX/ccauth" version
