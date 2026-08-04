#!/usr/bin/env bash
# Thin wrapper around localize.py — see that file's docstring for full usage.
#
# Examples:
#   ./scripts/localize.sh --check
#   ./scripts/localize.sh --list --lang de
#   ./scripts/localize.sh --get --lang en --key node.title
#   ./scripts/localize.sh --write --lang es --key node.checkingNodeStatusTitle "Comprobando estado"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"

exec "$PYTHON_BIN" "$SCRIPT_DIR/localize.py" "$@"
