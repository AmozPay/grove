#!/bin/sh
# Run every test. LEAF_BIN_DIR (a folder with the Leaf binaries) enables
# the tests that check the plugin against the real tools.
cd "$(dirname "$0")/.." || exit 1
status=0
sh tests/test_launcher.sh || status=1
python3 scripts/build.py --check || status=1
python3 tests/test_plugin.py || status=1
python3 tests/test_against_leaf.py || status=1
exit $status
