#!/usr/bin/env bash
# NixOS installer — uses nixos-anywhere with --phases to compute resume_offset
# before the final install. Run on a NixOS live USB (≥ 23.05).
#
# Usage:
#   sudo ./install.sh
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${RED}[WARN]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  warn "Run as root (sudo ./install.sh)"
  exit 1
fi

export NIX_CONFIG="experimental-features = nix-command flakes"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "\n${BOLD}═══ NixOS Installer (nixos-anywhere) ═══${NC}\n"

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
info "LUKS encryption passphrase (disk unlock at boot):"
read -rs -p "Passphrase: " LUKS_PASS
echo ""
read -rs -p "Confirm: " LUKS_PASS2
echo ""
if [[ "$LUKS_PASS" != "$LUKS_PASS2" ]]; then
  warn "Passphrases do not match!"; exit 1
fi

echo ""
info "Login password for user '$USERNAME':"
read -rs -p "Password: " USER_PASS
echo ""
read -rs -p "Confirm: " USER_PASS2
echo ""
if [[ "$USER_PASS" != "$USER_PASS2" ]]; then
  warn "Passwords do not match!"; exit 1
fi

HASHED_PASSWORD=$(echo "$USER_PASS" | mkpasswd -m sha-512 -s)
unset USER_PASS USER_PASS2

echo ""
warn "ALL DATA ON $DISK WILL BE DESTROYED!"
read -rp "Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then echo "Aborted."; exit 1; fi

# ─── Write LUKS passphrase ────────────────────────────────────────────────
echo -n "$LUKS_PASS" > /tmp/luks-password
chmod 600 /tmp/luks-password
unset LUKS_PASS LUKS_PASS2

# ─── Write settings.nix (resumeOffset=0 for now) ─────────────────────────
cat > "$SCRIPT_DIR/settings.nix" << EOF
{
  disk = "$DISK";
  hostname = "$HOSTNAME";
  username = "$USERNAME";
  hashedPassword = "$HASHED_PASSWORD";
  resumeOffset = "0";
}
EOF

# ─── Stage for flake eval ─────────────────────────────────────────────────
git add -A 2>/dev/null || { git init -q && git add -A; }
ok "Configuration ready"

# ─── SSH setup (nixos-anywhere needs it even for localhost) ───────────────
SSH_KEY="/tmp/nixos-install-key"
rm -f "$SSH_KEY" "$SSH_KEY.pub"
ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -q
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat "$SSH_KEY.pub" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
systemctl start sshd 2>/dev/null || true
ssh-keyscan -H localhost >> /root/.ssh/known_hosts 2>/dev/null
ok "SSH to localhost ready"

NA_FLAGS=(
  --target-host "root@localhost"
  -i "$SSH_KEY"
  --ssh-option "StrictHostKeyChecking=no"
  --disk-encryption-keys /tmp/luks-password /tmp/luks-password
)

# ─── Phase 1: kexec + disko ──────────────────────────────────────────────
info "Phase 1/2: Partitioning disk..."
nix run github:nix-community/nixos-anywhere -- \
  --phases "kexec,disko" \
  --flake "$SCRIPT_DIR#$HOSTNAME" \
  "${NA_FLAGS[@]}"
ok "Disk partitioned and mounted"

# ─── Compute resume_offset from fresh swapfile ───────────────────────────
RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)
info "resume_offset = $RESUME_OFFSET"

# Update settings.nix with real offset
cat > "$SCRIPT_DIR/settings.nix" << EOF
{
  disk = "$DISK";
  hostname = "$HOSTNAME";
  username = "$USERNAME";
  hashedPassword = "$HASHED_PASSWORD";
  resumeOffset = "$RESUME_OFFSET";
}
EOF
git add -A
ok "settings.nix updated with resume_offset"

# ─── Prepare extra-files (config for /etc/nixos) ─────────────────────────
EXTRA="/tmp/nixos-extra-files"
rm -rf "$EXTRA"
mkdir -p "$EXTRA/etc/nixos"
cp "$SCRIPT_DIR"/*.nix "$EXTRA/etc/nixos/"
cp "$SCRIPT_DIR"/flake.lock "$EXTRA/etc/nixos/" 2>/dev/null || true

# ─── Phase 2: install ────────────────────────────────────────────────────
info "Phase 2/2: Installing NixOS (this may take a while)..."
nix run github:nix-community/nixos-anywhere -- \
  --phases "install" \
  --flake "$SCRIPT_DIR#$HOSTNAME" \
  --generate-hardware-config nixos-generate-config ./hardware-configuration.nix \
  --extra-files "$EXTRA" \
  "${NA_FLAGS[@]}"
ok "NixOS installed"

# ─── Cleanup ──────────────────────────────────────────────────────────────
rm -f /tmp/luks-password "$SSH_KEY" "$SSH_KEY.pub"
rm -rf "$EXTRA"

# ─── Done ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo "  Disk:     $DISK"
echo "  Hostname: $HOSTNAME"
echo "  User:     $USERNAME"
echo ""
info "On reboot: Plymouth shows LUKS prompt → enter passphrase → log in as $USERNAME"
info "Hibernation is configured from first boot (resume_offset=$RESUME_OFFSET)"
echo ""
read -rp "Reboot now? [Y/n]: " DO_REBOOT
if [[ "${DO_REBOOT,,}" != "n" ]]; then
  reboot
fi
