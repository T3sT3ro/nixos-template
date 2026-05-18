#!/usr/bin/env bash
# Send all nix-creation files to the target machine via netcat.
# Usage: ./send.sh [host] [port]
#   Defaults: host=192.168.0.6  port=3333
#
# On the RECEIVING machine, run first:
#   cd /tmp && nc -l -p 3333 | tar xz
#
# This creates /tmp/nixcfg/ with all .nix files and /tmp/guide.md

set -euo pipefail

HOST="${1:-192.168.0.6}"
PORT="${2:-3333}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Packing and sending to $HOST:$PORT ..."
echo "Make sure the receiver is running:  cd /tmp && nc -l -p $PORT | tar xz"
echo ""
read -p "Press Enter when receiver is ready..."

tar cz -C "$SCRIPT_DIR" guide.md nixcfg/ | nc "$HOST" "$PORT"

echo "Done. Files sent:"
echo "  /tmp/guide.md"
echo "  /tmp/nixcfg/disko.nix"
echo "  /tmp/nixcfg/flake.nix"
echo "  /tmp/nixcfg/configuration.nix"
echo "  /tmp/nixcfg/home.nix"
