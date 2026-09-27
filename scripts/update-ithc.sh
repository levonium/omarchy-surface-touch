#!/usr/bin/env bash
# Refresh ithc-dkms/ithc/ from a linux-surface ithc patch.
#
# Usage:
#   scripts/update-ithc.sh <kernel-series> [repo] [ref]
#
# Examples:
#   scripts/update-ithc.sh 7.3                                   # official repo, master
#   scripts/update-ithc.sh 7.2 Apiznel/linux-surface 7.2          # a PR's fork/branch
#
# Only touches ithc-dkms/ithc/ and the pkgver in ithc-dkms/PKGBUILD.
# Review the diff with `git diff` before building.

set -euo pipefail

series="${1:?usage: $0 <kernel-series> [repo] [ref]}"
repo="${2:-linux-surface/linux-surface}"
ref="${3:-master}"

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Fetching patches/$series from $repo@$ref"
git clone -q --depth 1 --branch "$ref" "https://github.com/$repo.git" "$work/ls"

patch="$(ls "$work/ls/patches/$series/"*ithc*.patch 2>/dev/null | head -1 || true)"
if [[ -z "$patch" ]]; then
  echo "No ithc patch found in patches/$series of $repo@$ref" >&2
  exit 1
fi
echo "Using $(basename "$patch")"

mkdir "$work/tree"
git -C "$work/tree" init -q
git -C "$work/tree" apply --include='drivers/hid/ithc/*' "$patch"

rm -rf "$root/ithc-dkms/ithc"
mkdir "$root/ithc-dkms/ithc"
cp "$work/tree/drivers/hid/ithc/"*.c "$work/tree/drivers/hid/ithc/"*.h \
   "$work/tree/drivers/hid/ithc/Kbuild" "$root/ithc-dkms/ithc/"

commit="$(git -C "$work/ls" rev-parse --short HEAD)"
pkgver="$series.$(date +%Y%m%d)"
sed -i "s/^pkgver=.*/pkgver=$pkgver/; s/^pkgrel=.*/pkgrel=1/" "$root/ithc-dkms/PKGBUILD"

echo
echo "Updated ithc-dkms to $pkgver (source: $repo@$ref, commit $commit)."
echo "Record the source in README.md, review 'git diff', then rebuild:"
echo "  cd ithc-dkms && makepkg -si"
