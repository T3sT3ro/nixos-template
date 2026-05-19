#!/usr/bin/env bash
# Post-install: compute resume_offset for hibernation and rebuild.
# Run ONCE after first boot into the installed system.
#
# Usage:
#   sudo ./post-install.sh
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo ./post-install.sh)"
  exit 1
fi

NIXOS_DIR="/etc/nixos"
SETTINGS="$NIXOS_DIR/settings.nix"

if [[ ! -f "$SETTINGS" ]]; then
  echo "Cannot find $SETTINGS"
  exit 1
fi

# ─── Compute resume_offset ────────────────────────────────────────────────
RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /swap/swapfile)
info "resume_offset = $RESUME_OFFSET"

# ─── Update settings.nix ─────────────────────────────────────────────────
sed -i "s|resumeOffset = \"[^\"]*\"|resumeOffset = \"$RESUME_OFFSET\"|" "$SETTINGS"
ok "Updated $SETTINGS"

# ─── Rebuild ──────────────────────────────────────────────────────────────
HOSTNAME=$(grep 'hostname' "$SETTINGS" | sed 's/.*"\(.*\)".*/\1/')
info "Rebuilding NixOS (flake: $NIXOS_DIR#$HOSTNAME)..."

cd "$NIXOS_DIR"
git add -A 2>/dev/null || true
nixos-rebuild boot --flake ".#$HOSTNAME"

ok "Done! Hibernation will work after next reboot."
echo -e "  Test with: ${BOLD}systemctl hibernate${NC}"
