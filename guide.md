# NixOS Installation — LUKS + BTRFS + Disko + Flakes + Niri + Noctalia

## Architecture

```
┌─────────────────────────────────────────────┐
│ DISK (GPT)                                  │
├──────────┬──────────────────────────────────┤
│ Part 1   │ Part 2                           │
│ EFI/FAT  │ LUKS2 ("nixos")                  │
│ 1G       │ rest of disk                     │
│ /boot    │   └─ BTRFS                       │
│          │      ├─ @root  → /               │
│          │      ├─ @home  → /home           │
│          │      ├─ @nix   → /nix            │
│          │      ├─ @log   → /var/log        │
│          │      └─ @swap  → /swap           │
│          │           └─ swapfile (50G)       │
└──────────┴──────────────────────────────────┘

Boot flow:
  systemd-boot → initrd (systemd) → Plymouth splash
    → LUKS password prompt (graphical) → mount btrfs
    → Niri session → Noctalia shell spawns
```

**Subvolumes:**

| Subvolume | Mount     | Purpose |
|-----------|-----------|---------|
| `/root`   | `/`       | System root; rollback-friendly |
| `/home`   | `/home`   | User data; snapshot/backup independently |
| `/nix`    | `/nix`    | Nix store; reproducible, trivial to reconstruct — skip backups |
| `/log`    | `/var/log` | Persistent logs surviving rollbacks |
| `/swap`   | `/swap`   | Hosts 50G swapfile for hibernation; CoW disabled automatically by disko |

**Why `noatime`:** Prevents a CoW metadata write on every read. Critical on btrfs+SSD.

---

## 0. Set variables (adjust these!)

```bash
lsblk
DISK="/dev/nvme0n1"       # YOUR target disk
USERNAME="tooster"
HOSTNAME="nixbox"
```

---

## 1. Enable flakes in live USB

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
```

---

## 2. Transfer config files to live USB

On your source machine (where you ran `send.sh`), the files were sent.
On the live USB you should have received them, e.g.:

```bash
# On live USB — receive files (run BEFORE sending):
cd /tmp && nc -l -p 3333 | tar xz
# This creates /tmp/nixcfg/ with all .nix files
```

Or manually copy them to `/tmp/nixcfg/`.

---

## 3. Substitute placeholders in configs

```bash
cd /tmp/nixcfg

sed -i "s|__DISK__|$DISK|g" disko.nix
sed -i "s|__HOSTNAME__|$HOSTNAME|g" flake.nix configuration.nix
sed -i "s|__USERNAME__|$USERNAME|g" flake.nix configuration.nix home.nix
```

---

## 4. Write LUKS passphrase and run disko

```bash
read -s -p "LUKS passphrase: " PASSPHRASE && echo
echo -n "$PASSPHRASE" > /tmp/luks-password

nix run github:nix-community/disko -- --mode disko /tmp/nixcfg/disko.nix

# Verify
mount | grep /mnt
```

> WARNING: This erases ALL data on $DISK.

---

## 5. Get hibernation resume offset

```bash
RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)
echo "resume_offset = $RESUME_OFFSET"
```

---

## 6. Get LUKS partition UUID

```bash
# For nvme disks it's ${DISK}p2, for sata it's ${DISK}2
LUKS_UUID=$(blkid -s UUID -o value "${DISK}p2" 2>/dev/null \
         || blkid -s UUID -o value "${DISK}2")
echo "LUKS_UUID = $LUKS_UUID"
```

---

## 7. Substitute runtime values

```bash
sed -i "s|__LUKS_UUID__|$LUKS_UUID|" /tmp/nixcfg/configuration.nix
sed -i "s|__RESUME_OFFSET__|$RESUME_OFFSET|" /tmp/nixcfg/configuration.nix
```

---

## 8. Generate hardware-configuration.nix

```bash
nixos-generate-config --root /mnt --dir /tmp/nixcfg

# Remove auto-generated fileSystems and swapDevices — disko manages them
sed -i '/^\s*fileSystems\./,/^\s*};/d' /tmp/nixcfg/hardware-configuration.nix
sed -i '/^\s*swapDevices/,/^\s*\];/d' /tmp/nixcfg/hardware-configuration.nix
```

**Verify manually** that only kernel modules and hardware detection remain:
```bash
cat /tmp/nixcfg/hardware-configuration.nix
```

---

## 9. Install

```bash
mkdir -p /mnt/etc/nixos
cp /tmp/nixcfg/*.nix /mnt/etc/nixos/

nixos-install --flake /mnt/etc/nixos#$HOSTNAME --no-root-passwd
```

Set user password:
```bash
nixos-enter --root /mnt -c "passwd $USERNAME"
```

---

## 10. Reboot

```bash
reboot
```

Remove USB. Plymouth shows the LUKS prompt graphically. Enter passphrase → Niri starts → Noctalia shell spawns.

---

## Post-install checklist

| Task | How |
|------|-----|
| Init git repo | `cd /etc/nixos && sudo git init && sudo git add -A && sudo git commit -m "initial"` |
| Test hibernation | `systemctl hibernate` |
| Noctalia first-run | Setup wizard appears automatically on first launch |
| Keyd verify | CapsLock → F13; Shift+CapsLock → actual CapsLock toggle |
| Join AD (later) | Uncomment `services.sssd` in configuration.nix, fill domain/URL, rebuild |
| Restore from deja-dup | Open Deja Dup → Restore → point to old backup location (reads Ubuntu duplicity format) |
| Move config to remote | `cd /etc/nixos && git remote add origin <url> && git push -u origin main` |

---

## Key design decisions

- **Plymouth + `boot.initrd.systemd.enable = true`** — makes the LUKS prompt graphical within the Plymouth splash. Escape shows logs (hybrid boot).
- **Default `bgrt` Plymouth theme** — vendor logo, natively supports graphical LUKS password entry. Custom themes may not.
- **`allowDiscards = true` on LUKS** — enables TRIM for SSD longevity. Minimal theoretical info leak (which blocks are used); acceptable for desktop.
- **`hardware.nvidia.open = true`** — open-source kernel modules for Turing+ GPUs. Set `false` for pre-Turing.
- **Passwordless sudo** — disk is LUKS-encrypted; anyone at the keyboard already proved identity. Revisit if adding remote SSH or multiple users.
- **Flat (non-modular) structure** — good for initial install. Refactor into `hosts/`, `modules/`, `home/` subdirectories later when adding the git repo.
