# Helpers for the shell tests: `. tests/lib.sh`.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ok() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=1; }
# check "name" command...: passes when the command succeeds.
check() {
  _n="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$_n"; else fail "$_n"; fi
}
# check_not "name" command...: passes when the command fails.
check_not() {
  _n="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$_n"; else ok "$_n"; fi
}
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
finish() { [ "$FAILED" -eq 0 ]; }
