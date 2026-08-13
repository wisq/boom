#!/usr/bin/env bash
#
# Ensures prompt_toolkit (and its dependencies) are installed locally in
# this app's tree, then launches client.py.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/client"
VENDOR_DIR="$SCRIPT_DIR/vendor"
REQ_FILE="$SCRIPT_DIR/requirements.txt"
STAMP_FILE="$VENDOR_DIR/.requirements.stamp"

mkdir -p "$VENDOR_DIR"

if [ ! -f "$STAMP_FILE" ] || ! cmp -s "$REQ_FILE" "$STAMP_FILE"; then
  echo "Installing client dependencies into $VENDOR_DIR ..." >&2
  pip3 install \
    --disable-pip-version-check \
    --quiet \
    --upgrade \
    --target "$VENDOR_DIR" \
    -r "$REQ_FILE"
  cp "$REQ_FILE" "$STAMP_FILE"
fi

PYTHONPATH="$VENDOR_DIR${PYTHONPATH:+:$PYTHONPATH}" exec python3 "$SCRIPT_DIR/client.py" "$@"
