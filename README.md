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
│          │           └─ swapfile (50G)       │
└──────────┴──────────────────────────────────┘
```

## Installation

Boot the **NixOS minimal installer USB** (≥ 23.05). Connect to the internet.

### 1. Prepare

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
passwd root                  # needed for SSH to localhost
systemctl start sshd
```

### 2. Clone and install

```bash
nix-shell -p git
git clone https://github.com/T3sT3ro/nixos-template /tmp/nixcfg
cd /tmp/nixcfg
sudo ./install.sh
```

The script:
1. Prompts for disk, hostname, username, LUKS passphrase, and user password
2. Runs `nixos-anywhere --phases kexec,disko` to partition and format the disk
3. Computes `resume_offset` from the freshly created swapfile (hibernation works from first boot)
4. Runs `nixos-anywhere --phases install` to build and install the full system
5. Copies `.nix` and `flake.lock` to `/etc/nixos` via `--extra-files`
6. Reboots

### 3. First boot

Plymouth shows the graphical LUKS prompt → enter passphrase → log in as your user.

Everything (Niri, Noctalia, zsh, keyd, NVIDIA, hibernation) is ready from first boot.

---

## Manual installation

If you prefer running commands yourself:

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
git clone https://github.com/T3sT3ro/nixos-template /tmp/nixcfg
cd /tmp/nixcfg

# 1. Edit settings.nix
nano settings.nix

# 2. Write LUKS passphrase
echo -n "your-passphrase" > /tmp/luks-password && chmod 600 /tmp/luks-password

# 3. Set up SSH to localhost
passwd root && systemctl start sshd
ssh-keygen -t ed25519 -N "" -f /tmp/key -q
cat /tmp/key.pub >> /root/.ssh/authorized_keys

# 4. Stage files
git add -A

# 5. Phase 1: partition
nix run github:nix-community/nixos-anywhere -- \
  --phases kexec,disko \
  --flake .#HOSTNAME \
  --target-host root@localhost \
  -i /tmp/key \
  --ssh-option StrictHostKeyChecking=no \
  --disk-encryption-keys /tmp/luks-password /tmp/luks-password

# 6. Compute resume_offset and update settings.nix
OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)
sed -i "s|resumeOffset = \"[^\"]*\"|resumeOffset = \"$OFFSET\"|" settings.nix
git add -A

# 7. Phase 2: install
nix run github:nix-community/nixos-anywhere -- \
  --phases install \
  --flake .#HOSTNAME \
  --target-host root@localhost \
  -i /tmp/key \
  --ssh-option StrictHostKeyChecking=no \
  --disk-encryption-keys /tmp/luks-password /tmp/luks-password \
  --generate-hardware-config nixos-generate-config ./hardware-configuration.nix \
  --extra-files /tmp/nixos-extra-files

# 8. Reboot
reboot
```

---

## Day-to-day usage

```bash
cd /etc/nixos && git add -A
sudo nixos-rebuild switch --flake .#HOSTNAME
```

---

## What's in `/etc/nixos`

Only `.nix` files and `flake.lock` — everything needed for `nixos-rebuild`. No scripts.

| File | Purpose |
|------|---------|
| `flake.nix` | Inputs (nixpkgs, disko, home-manager, niri, noctalia) and system definition |
| `flake.lock` | Pinned dependency versions |
| `settings.nix` | Hardware-specific values (disk, hostname, user, resumeOffset) |
| `disko.nix` | Declarative disk layout |
| `configuration.nix` | System config (boot, NVIDIA, keyd, locale, services) |
| `hardware-configuration.nix` | Auto-generated kernel modules and hardware detection |
| `home.nix` | Home Manager config (Noctalia, niri settings, packages) |

---

## Design decisions

| Decision | Rationale |
|----------|-----------|
| nixos-anywhere `--phases` | Compute `resume_offset` between disko and install — hibernation works from first boot |
| `--extra-files` | Places config at `/etc/nixos` before reboot — no unreachable steps |
| `initialHashedPassword` | User can log in immediately after automatic reboot |
| `settings.nix` attrset | Single source of truth, no sed on `.nix` files |
| `boot.initrd.systemd.enable` | Required for graphical Plymouth LUKS prompt |
| `allowDiscards = true` | TRIM for SSD longevity |
| `hardware.nvidia.open = true` | Open kernel modules for Turing+ GPUs |
| Passwordless sudo | LUKS-encrypted disk = physical access requires passphrase |
