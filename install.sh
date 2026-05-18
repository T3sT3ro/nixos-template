#!/usr/bin/env bash
# NixOS Installer — LUKS + BTRFS + Disko + Flakes
# Run from NixOS live USB:
#   nix run github:YOUR_USER/nixos-config
#
# Or if you cloned the repo:
#   ./install.sh
set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${RED}[WARN]${NC} $*"; }
header() { echo -e "\n${BOLD}══════════════════════════════════════════${NC}"; echo -e "${BOLD}  $*${NC}"; echo -e "${BOLD}══════════════════════════════════════════${NC}\n"; }

# ─── Preflight ─────────────────────────────────────────────────────────────
header "NixOS Installer"

if [[ $EUID -ne 0 ]]; then
  warn "This script must be run as root (or with sudo)."
  exit 1
fi

export NIX_CONFIG="experimental-features = nix-command flakes"

# ─── Locate flake directory ────────────────────────────────────────────────
# If run via `nix run`, the script is in the nix store; FLAKE_DIR points to the repo.
# If run directly from a clone, use the script's directory.
if [[ -n "${FLAKE_DIR:-}" ]]; then
  FLAKE="$FLAKE_DIR"
elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/flake.nix" ]]; then
  FLAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  # Running from nix run — clone to tmp
  info "Cloning config repo to /tmp/nixos-config..."
  FLAKE="/tmp/nixos-config"
  if [[ -d "$FLAKE" ]]; then
    rm -rf "$FLAKE"
  fi
  nix flake clone --dest "$FLAKE" "$(cat /proc/self/cmdline | tr '\0' '\n' | grep 'github:' | head -1 || echo 'github:tooster/nixos-config')"
fi

# ─── Gather parameters ────────────────────────────────────────────────────
header "Configuration"

echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "^loop"
echo ""
read -p "Target disk [/dev/nvme0n1]: " DISK
DISK="${DISK:-/dev/nvme0n1}"

if [[ ! -b "$DISK" ]]; then
  warn "$DISK is not a valid block device!"
  exit 1
fi

read -p "Hostname [nixbox]: " HOSTNAME
HOSTNAME="${HOSTNAME:-nixbox}"

read -p "Username [tooster]: " USERNAME
USERNAME="${USERNAME:-tooster}"

echo ""
warn "ALL DATA ON $DISK WILL BE DESTROYED!"
read -p "Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
info "Enter LUKS encryption passphrase:"
read -s -p "Passphrase: " PASSPHRASE
echo ""
read -s -p "Confirm passphrase: " PASSPHRASE2
echo ""

if [[ "$PASSPHRASE" != "$PASSPHRASE2" ]]; then
  warn "Passphrases do not match!"
  exit 1
fi

echo -n "$PASSPHRASE" > /tmp/luks-password
unset PASSPHRASE PASSPHRASE2

# ─── Prepare config ───────────────────────────────────────────────────────
header "Preparing configuration"

# Copy flake to a writable working directory
WORKDIR="/tmp/nixos-install-workdir"
rm -rf "$WORKDIR"
cp -r "$FLAKE" "$WORKDIR"
chmod -R u+w "$WORKDIR"

# Patch disko disk device
sed -i "s|lib.mkDefault \"/dev/nvme0n1\"|lib.mkDefault \"$DISK\"|" "$WORKDIR/disko.nix"

# Patch hostname and username in flake.nix
sed -i "s|__HOSTNAME__|$HOSTNAME|g" "$WORKDIR/flake.nix"
sed -i "s|__USERNAME__|$USERNAME|g" "$WORKDIR/flake.nix" "$WORKDIR/home.nix"

# Patch configuration.nix
sed -i "s|__HOSTNAME__|$HOSTNAME|g" "$WORKDIR/configuration.nix"
sed -i "s|__USERNAME__|$USERNAME|g" "$WORKDIR/configuration.nix"

ok "Config patched for disk=$DISK hostname=$HOSTNAME user=$USERNAME"

# ─── Run Disko ────────────────────────────────────────────────────────────
header "Partitioning and formatting (disko)"

nix run github:nix-community/disko -- --mode disko "$WORKDIR/disko.nix"

ok "Disk partitioned and mounted"

# ─── Compute hibernation resume offset ───────────────────────────────────
header "Computing hibernation resume offset"

RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)
info "resume_offset = $RESUME_OFFSET"

# Determine LUKS UUID
# nvme: ${DISK}p2, sata/virt: ${DISK}2
if [[ "$DISK" == *nvme* ]] || [[ "$DISK" == *mmcblk* ]]; then
  LUKS_PART="${DISK}p2"
else
  LUKS_PART="${DISK}2"
fi
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART")
info "LUKS UUID = $LUKS_UUID"

# Patch configuration.nix with runtime values
sed -i "s|__LUKS_UUID__|$LUKS_UUID|" "$WORKDIR/configuration.nix"
sed -i "s|__RESUME_OFFSET__|$RESUME_OFFSET|" "$WORKDIR/configuration.nix"

ok "Boot configuration patched"

# ─── Generate hardware-configuration.nix ──────────────────────────────────
header "Generating hardware-configuration.nix"

nixos-generate-config --root /mnt --dir "$WORKDIR"

# Remove auto-generated fileSystems and swapDevices — disko handles them
sed -i '/^\s*fileSystems\./,/^\s*};/d' "$WORKDIR/hardware-configuration.nix"
sed -i '/^\s*swapDevices/,/^\s*\];/d' "$WORKDIR/hardware-configuration.nix"

ok "hardware-configuration.nix generated (fileSystems stripped — disko manages them)"

# ─── Install NixOS ────────────────────────────────────────────────────────
header "Installing NixOS"

mkdir -p /mnt/etc/nixos
cp "$WORKDIR"/*.nix /mnt/etc/nixos/

# Initialize a git repo (flakes require it to see files)
cd /mnt/etc/nixos
git init -q
git add -A
git commit -q -m "initial: generated by installer"

info "Running nixos-install (this may take a while)..."
nixos-install --flake "/mnt/etc/nixos#$HOSTNAME" --no-root-passwd

# ─── Set user password ────────────────────────────────────────────────────
header "Set user password"

info "Set password for $USERNAME:"
nixos-enter --root /mnt -c "passwd $USERNAME"

# ─── Cleanup ──────────────────────────────────────────────────────────────
rm -f /tmp/luks-password

# ─── Done ─────────────────────────────────────────────────────────────────
header "Installation complete!"

echo -e "
${GREEN}Next steps:${NC}
  1. Reboot:  ${BOLD}reboot${NC}
  2. Remove USB stick
  3. Plymouth will show LUKS passphrase prompt
  4. Log in as ${BOLD}$USERNAME${NC}
  5. Push your config:
       cd /etc/nixos
       git remote add origin <your-repo-url>
       git push -u origin main
"
