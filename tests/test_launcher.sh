#!/bin/sh
# The launcher downloads a pinned archive once, verifies its sha256, caches it,
# and refuses anything else. Hermetic: the "release" is a local file:// folder
# holding an archive of stub programs.
. "$(dirname "$0")/lib.sh"
RUN="$ROOT/core/bin/run"
unset LEAF_BIN_DIR   # the tests below are about the download, not the override

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) target=x86_64-unknown-linux-gnu ;;
  Linux/aarch64 | Linux/arm64) target=aarch64-unknown-linux-gnu ;;
  Darwin/x86_64) target=x86_64-apple-darwin ;;
  Darwin/arm64) target=aarch64-apple-darwin ;;
  *) echo "skip: unsupported host"; exit 0 ;;
esac
key="$(printf '%s' "$target" | tr '-' '_')"

# A release of three stub programs that print their name and arguments.
name="leaf-9.9.9-$target"
mkdir -p "$TMP/release" "$TMP/build/$name"
for bin in leaf-mcp leaf-mcp-editor leaf; do
  printf '#!/bin/sh\necho "%s $*"\n' "$bin" > "$TMP/build/$name/$bin"
  chmod +x "$TMP/build/$name/$bin"
done
tar -czf "$TMP/release/$name.tar.gz" -C "$TMP/build" "$name"
sum="$(sha256 "$TMP/release/$name.tar.gz")"

pin() { # pin <sha256>
  cat > "$TMP/release.env" <<ENV
VERSION=9.9.9
BASE_URL=file://$TMP/release
SHA256_$key=$1
ENV
}
export GROVE_RELEASE_FILE="$TMP/release.env"
export GROVE_CACHE="$TMP/cache"

pin "$sum"
out="$("$RUN" leaf-mcp-editor --wiki /x 2>"$TMP/err")"
[ "$out" = "leaf-mcp-editor --wiki /x" ] && ok "downloads, verifies and runs the pinned binary" || fail "runs the binary: got '$out'"
grep -q "downloading" "$TMP/err" && ok "says on stderr that it downloads" || fail "stderr note"
[ -z "$(cat "$TMP/err" | grep -v '^grove:')" ] && ok "prints nothing else on stderr" || fail "stderr noise"

rm "$TMP/release/$name.tar.gz"
out="$("$RUN" leaf-mcp one two 2>"$TMP/err")"
[ "$out" = "leaf-mcp one two" ] && ok "second run uses the cache (the release is gone)" || fail "cache: got '$out'"
! grep -q "downloading" "$TMP/err" && ok "no download the second time" || fail "downloaded again"

# Hosts that set PLUGIN_DATA (Agent Plugins v1) get their cache there, when GROVE_CACHE is not set.
rm -rf "$TMP/cache"
tar -czf "$TMP/release/$name.tar.gz" -C "$TMP/build" "$name"
pin "$sum"
out="$(env -u GROVE_CACHE PLUGIN_DATA="$TMP/plugin-data" "$RUN" leaf one 2>/dev/null)"
[ "$out" = "leaf one" ] && [ -x "$TMP/plugin-data/bin/9.9.9-$target/leaf" ] && ok "caches in PLUGIN_DATA" || fail "PLUGIN_DATA cache: got '$out'"

# A wrong hash is refused and nothing is cached or run.
rm -rf "$TMP/cache"
tar -czf "$TMP/release/$name.tar.gz" -C "$TMP/build" "$name"
pin "0000000000000000000000000000000000000000000000000000000000000000"
if "$RUN" leaf >"$TMP/out" 2>"$TMP/err"; then fail "a wrong checksum must fail"; else ok "a wrong checksum fails"; fi
grep -q "checksum mismatch" "$TMP/err" && ok "names the checksum mismatch" || fail "mismatch message"
[ ! -s "$TMP/out" ] && ok "runs nothing on a mismatch" || fail "ran on a mismatch"
[ ! -e "$TMP/cache/bin/9.9.9-$target" ] && ok "caches nothing on a mismatch" || fail "cached a bad archive"

# Configuration problems say what is missing.
check_not "unknown binary name" "$RUN" rm
printf 'VERSION=9.9.9\nBASE_URL=\n' > "$TMP/release.env"
if "$RUN" leaf >/dev/null 2>"$TMP/err"; then fail "no pinned hash must fail"; else ok "no pinned hash fails"; fi
grep -q "SHA256_$key" "$TMP/err" && ok "names the missing hash" || fail "missing hash message"
printf 'VERSION=9.9.9\nSHA256_%s=%s\n' "$key" "$sum" > "$TMP/release.env"
if "$RUN" leaf >/dev/null 2>"$TMP/err"; then fail "no BASE_URL must fail"; else ok "no BASE_URL fails"; fi
grep -q "BASE_URL" "$TMP/err" && ok "names the missing BASE_URL" || fail "BASE_URL message"

# Development override: no download, no release file needed.
unset GROVE_RELEASE_FILE
out="$(LEAF_BIN_DIR="$TMP/build/$name" "$RUN" leaf hello)"
[ "$out" = "leaf hello" ] && ok "LEAF_BIN_DIR runs a local build" || fail "bin dir: got '$out'"

# An unsupported platform is named.
mkdir -p "$TMP/shim"
printf '#!/bin/sh\ncase "$1" in -s) echo Plan9;; -m) echo vax;; esac\n' > "$TMP/shim/uname"
chmod +x "$TMP/shim/uname"
export GROVE_RELEASE_FILE="$TMP/release.env"
if PATH="$TMP/shim:$PATH" "$RUN" leaf >/dev/null 2>"$TMP/err"; then fail "unsupported platform must fail"; else ok "unsupported platform fails"; fi
grep -q "Plan9/vax" "$TMP/err" && ok "names the platform" || fail "platform message"
finish
