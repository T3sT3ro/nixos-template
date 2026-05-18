{ config, pkgs, inputs, lib, ... }:
{
  # ─── Boot ───────────────────────────────────────────────────────────────
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      systemd.enable = true; # required for graphical LUKS prompt in Plymouth
    };

    # Hibernation
    resumeDevice = "/dev/mapper/nixos";
    kernelParams = [
      "resume_offset=__RESUME_OFFSET__"
      "quiet"
      "splash"
      "udev.log_level=3"
    ];

    # Plymouth: graphical boot with LUKS password prompt
    # Default "bgrt" theme natively supports password entry
    # Press Escape during boot to see logs
    plymouth.enable = true;

    supportedFilesystems = [ "btrfs" ];
  };

  # ─── Networking ─────────────────────────────────────────────────────────
  networking = {
    hostName = "__HOSTNAME__";
    networkmanager.enable = true;
  };

  # ─── Locale ─────────────────────────────────────────────────────────────
  time.timeZone = "Europe/Warsaw";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "pl_PL.UTF-8";
      LC_MONETARY = "pl_PL.UTF-8";
      LC_PAPER = "pl_PL.UTF-8";
      LC_MEASUREMENT = "pl_PL.UTF-8";
      LC_ADDRESS = "pl_PL.UTF-8";
      LC_TELEPHONE = "pl_PL.UTF-8";
      LC_NAME = "pl_PL.UTF-8";
    };
  };

  console.keyMap = "pl";
  services.xserver.xkb.layout = "pl";

  # ─── NVIDIA ─────────────────────────────────────────────────────────────
  hardware = {
    graphics.enable = true;
    nvidia = {
      modesetting.enable = true;
      open = true; # Turing+ (RTX 20xx / GTX 16xx and newer); set false for older
      powerManagement.enable = true;
    };
    bluetooth.enable = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  # ─── Niri (Wayland compositor) ──────────────────────────────────────────
  programs.niri.enable = true;

  # ─── Keyd (keyboard remapping) ──────────────────────────────────────────
  # CapsLock → F13 (useful as a hyper/compose key)
  # Shift+CapsLock → actual CapsLock toggle
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          capslock = "f13";
        };
        "shift" = {
          capslock = "capslock";
        };
      };
    };
  };

  # ─── User ───────────────────────────────────────────────────────────────
  programs.zsh.enable = true;

  users.users.__USERNAME__ = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.zsh;
  };

  # Passwordless sudo for wheel group.
  # Justification: disk is LUKS-encrypted — physical access already requires
  # the passphrase. Revisit if adding SSH access or multiple users.
  security.sudo.wheelNeedsPassword = false;

  # ─── SSSD (prepared for AD join — uncomment when ready) ─────────────────
  # services.sssd = {
  #   enable = true;
  #   config = ''
  #     [sssd]
  #     domains = YOURDOMAIN
  #     services = nss, pam
  #
  #     [domain/YOURDOMAIN]
  #     id_provider = ad
  #     auth_provider = ad
  #     access_provider = ad
  #     ad_domain = YOURDOMAIN
  #     ad_server = your.ad.server.url
  #     krb5_realm = YOURREALM
  #     ldap_id_mapping = true
  #     default_shell = /run/current-system/sw/bin/zsh
  #     fallback_homedir = /home/%u
  #   '';
  # };

  # ─── Services ───────────────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };

  # ─── Nix settings ──────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nixpkgs.config.allowUnfree = true;

  # ─── System packages (minimal — user packages go in home.nix) ───────────
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    pciutils
  ];

  system.stateVersion = "25.05";
}
