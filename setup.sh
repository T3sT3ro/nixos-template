#!/usr/bin/env bash
# Pre-install helper — generates settings.nix and prepares for nixos-anywhere.
# Run on the NixOS live USB BEFORE running nixos-anywhere.
#
# Usage:
#   sudo ./setup.sh
#   # then follow printed instructions to run nixos-anywhere
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${RED}[WARN]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  warn "Run as root (sudo ./setup.sh)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "\n${BOLD}═══ NixOS Setup ═══${NC}\n"

# ─── Gather parameters ────────────────────────────────────────────────────
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "^loop"
echo ""
read -rp "Target disk [/dev/nvme0n1]: " DISK
DISK="${DISK:-/dev/nvme0n1}"

if [[ ! -b "$DISK" ]]; then
  warn "$DISK is not a valid block device!"
  exit 1
fi

read -rp "Hostname [nixbox]: " HOSTNAME
HOSTNAME="${HOSTNAME:-nixbox}"

read -rp "Username [tooster]: " USERNAME
USERNAME="${USERNAME:-tooster}"

echo ""
info "Enter LUKS encryption passphrase:"
read -rs -p "Passphrase: " PASSPHRASE
echo ""
read -rs -p "Confirm: " PASSPHRASE2
echo ""

if [[ "$PASSPHRASE" != "$PASSPHRASE2" ]]; then
  warn "Passphrases do not match!"
  exit 1
fi

echo ""
info "Enter login password for user '$USERNAME':"
read -rs -p "Password: " USER_PASSWORD
echo ""
read -rs -p "Confirm: " USER_PASSWORD2
echo ""

if [[ "$USER_PASSWORD" != "$USER_PASSWORD2" ]]; then
  warn "Passwords do not match!"
  exit 1
fi

# Hash the password (mkpasswd is in nixos installer)
HASHED_PASSWORD=$(echo "$USER_PASSWORD" | mkpasswd -m sha-512 -s)
unset USER_PASSWORD USER_PASSWORD2

# ─── Write settings.nix ──────────────────────────────────────────────────
cat > "$SCRIPT_DIR/settings.nix" << EOF
{
  disk = "$DISK";
  hostname = "$HOSTNAME";
  username = "$USERNAME";
  hashedPassword = "$HASHED_PASSWORD";
  resumeOffset = "0"; # updated after first boot via post-install.sh
}
EOF

ok "settings.nix written"

# ─── Write LUKS password file ─────────────────────────────────────────────
echo -n "$PASSPHRASE" > /tmp/luks-password
chmod 600 /tmp/luks-password
unset PASSPHRASE PASSPHRASE2

ok "LUKS passphrase saved to /tmp/luks-password"

# ─── Prepare --extra-files tree ───────────────────────────────────────────
# nixos-anywhere --extra-files copies this tree to / on the target after install.
# This places the config at /etc/nixos for future nixos-rebuild.
EXTRA="/tmp/nixos-extra-files"
rm -rf "$EXTRA"
mkdir -p "$EXTRA/etc/nixos"
cp "$SCRIPT_DIR"/*.nix "$EXTRA/etc/nixos/"
cp "$SCRIPT_DIR"/*.sh "$EXTRA/etc/nixos/" 2>/dev/null || true
cp "$SCRIPT_DIR"/.gitignore "$EXTRA/etc/nixos/" 2>/dev/null || true
cp "$SCRIPT_DIR"/flake.lock "$EXTRA/etc/nixos/" 2>/dev/null || true

ok "Extra files prepared (will be placed at /etc/nixos on target)"

# ─── Ensure git tracks files (required by flakes) ─────────────────────────
git add -A 2>/dev/null || { git init -q && git add -A; }

ok "Files staged for flake evaluation"

# ─── Print next steps ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══ Ready! Run nixos-anywhere: ═══${NC}"
echo ""
echo -e "  ${GREEN}nix run github:nix-community/nixos-anywhere -- \\"
echo -e "    --flake ${SCRIPT_DIR}#${HOSTNAME} \\"
echo -e "    --target-host root@localhost \\"
echo -e "    --disk-encryption-keys /tmp/luks-password /tmp/luks-password \\"
echo -e "    --generate-hardware-config nixos-generate-config ./hardware-configuration.nix \\"
echo -e "    --extra-files ${EXTRA}${NC}"
echo ""
info "Make sure sshd is running and you can ssh root@localhost:"
echo "    passwd root        # set a temporary root password"
echo "    systemctl start sshd"
echo ""
info "After installation and reboot, run: sudo /etc/nixos/post-install.sh"
info "(enables hibernation by computing resume_offset and rebuilding)"
