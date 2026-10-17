#!/bin/sh
# Pin a Wikileaf release into core/release.env:
#
#   scripts/pin-release.sh <BASE_URL> <DIR-WITH-ARCHIVES>
#
# BASE_URL is where wikileaf-<version>-<target>.tar.gz files are published
# (https://... or file:///...). Every archive in the folder is hashed, so the
# plugin runs only what was pinned here.
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <BASE_URL> <DIR-WITH-ARCHIVES>" >&2; exit 2; }
base="$1"
dir="$2"
out="$(cd "$(dirname "$0")/.." && pwd)/core/release.env"
version=""
lines=""
for archive in "$dir"/wikileaf-*.tar.gz; do
  [ -f "$archive" ] || { echo "no wikileaf-*.tar.gz in $dir" >&2; exit 1; }
  name="$(basename "$archive" .tar.gz)"        # wikileaf-<version>-<target>
  rest="${name#wikileaf-}"
  v="${rest%%-*}"
  target="${rest#*-}"
  [ -z "$version" ] || [ "$version" = "$v" ] || { echo "archives of different versions in $dir" >&2; exit 1; }
  version="$v"
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$archive" | cut -d' ' -f1)"
  else
    sum="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
  fi
  key="$(printf '%s' "$target" | tr '-' '_')"
  lines="$lines
SHA256_$key=$sum"
done
{
  echo "# The Wikileaf release this plugin runs. Pinned: the launcher refuses an"
  echo "# archive whose sha256 differs. Regenerate with scripts/pin-release.sh."
  echo "VERSION=$version"
  echo "BASE_URL=$base"
  printf '%s\n' "$lines" | sed '/^$/d'
} > "$out"
echo "pinned $version in $out"
