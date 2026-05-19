# NixOS Configuration — LUKS + BTRFS + Disko + Niri + Noctalia

## Disk layout

```
┌─────────────────────────────────────────────┐
│ DISK (GPT)                                  │
├──────────┬──────────────────────────────────┤
│ Part 1   │ Part 2                           │
│ EFI/FAT  │ LUKS2 ("nixos")                  │
│ 1G       │ rest of disk                     │
│ /boot    │   └─ BTRFS                       │
│          │      ├─ @      → /               │
│          │      ├─ @home  → /home           │
│          │      ├─ @nix   → /nix            │
│          │      ├─ @log   → /var/log        │
│          │      └─ @swap  → /swap           │
│          │           └─ swapfile (50G)      │
└──────────┴──────────────────────────────────┘
```

## Installation

Boot the **NixOS minimal installer USB** (≥ 23.05). Connect to the internet.

### 1. Prepare the live environment

```bash
# Enable flakes
export NIX_CONFIG="experimental-features = nix-command flakes"

# Set root password (needed for SSH to localhost)
passwd root

# Ensure sshd is running
systemctl start sshd
```

### 2. Clone and configure

```bash
nix-shell -p git
git clone https://github.com/T3sT3ro/nixos-template /tmp/nixcfg
cd /tmp/nixcfg

# Run the setup helper — prompts for disk, hostname, username, LUKS passphrase
sudo ./setup.sh
```

Or configure manually:

```bash
# Edit settings.nix with your values
nano settings.nix

# Write LUKS passphrase (used by disko during format only)
echo -n "your-passphrase" > /tmp/luks-password && chmod 600 /tmp/luks-password

# Stage for flake evaluation
git add -A
```

### 3. Install with nixos-anywhere

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake /tmp/nixcfg#HOSTNAME \
  --target-host root@localhost \
  --disk-encryption-keys /tmp/luks-password /tmp/luks-password \
  --generate-hardware-config nixos-generate-config ./hardware-configuration.nix
```

Replace `HOSTNAME` with the value you set in `settings.nix`.

This single command:
- Partitions the disk (disko: GPT + LUKS2 + BTRFS subvolumes)
- Builds the NixOS system closure
- Installs everything to the target disk
- Generates `hardware-configuration.nix` from detected hardware

### 4. Copy config to installed system

```bash
# After nixos-anywhere finishes, config is at /mnt/etc/nixos
# Copy our source (with the generated hardware-configuration.nix) for future rebuilds
cp /tmp/nixcfg/*.nix /tmp/nixcfg/*.lock /tmp/nixcfg/*.sh /mnt/etc/nixos/ 2>/dev/null || true
cp /tmp/nixcfg/.gitignore /mnt/etc/nixos/ 2>/dev/null || true
cd /mnt/etc/nixos && git init -q && git add -A
```

### 5. Set user password and reboot

```bash
nixos-enter --root /mnt -c "passwd USERNAME"
reboot
```

### 6. Post-install: enable hibernation

After first boot, run once to compute the swapfile offset:

```bash
sudo /etc/nixos/post-install.sh
sudo reboot
```

This updates `resumeOffset` in `settings.nix` and rebuilds. Hibernation works after this reboot.

---

## Day-to-day usage

```bash
# Edit configuration
sudo nano /etc/nixos/configuration.nix

# Rebuild
cd /etc/nixos && git add -A
sudo nixos-rebuild switch --flake .#HOSTNAME
```

---

## How nixos-anywhere works here

[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) is the standard NixOS community tool for declarative installation. It:

1. Detects the NixOS installer environment (`VARIANT_ID=installer`) — skips kexec
2. Runs disko to partition/format/mount the disk
3. Builds and installs the NixOS closure from the flake
4. Reboots into the installed system

The `--disk-encryption-keys` flag copies the LUKS passphrase into the installer environment where disko's `passwordFile` expects it. At runtime, Plymouth prompts for the passphrase interactively (systemd-initrd).

---

## Design decisions

| Decision | Rationale |
|----------|-----------|
| `settings.nix` attrset | Single source of truth for hardware-specific values, no sed templating |
| Split `resumeOffset` to post-install | Swapfile offset can only be computed after disko creates it; avoids split-phase hacks |
| `boot.initrd.systemd.enable` | Required for graphical Plymouth LUKS prompt |
| `allowDiscards = true` | TRIM for SSD longevity; minimal info leak, acceptable for desktop |
| `hardware.nvidia.open = true` | Open kernel modules for Turing+ GPUs |
| Passwordless sudo | Disk is LUKS-encrypted; physical access already requires the passphrase |
| `noatime` on all subvolumes | Avoids CoW metadata write on every read (critical for btrfs+SSD) |
