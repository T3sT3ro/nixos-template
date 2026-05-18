{ pkgs, inputs, config, settings, ... }:
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  home.username = settings.username;
  home.homeDirectory = "/home/${settings.username}";
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  # ─── Zsh (minimal — personal dotfiles layered later) ─────────────────────
  programs.zsh.enable = true;

  # ─── Starship prompt ─────────────────────────────────────────────────────
  programs.starship.enable = true;

  # ─── Git ─────────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    # Uncomment and fill:
    # userName = "Your Name";
    # userEmail = "you@example.com";
  };

  # ─── Noctalia Shell (desktop shell: bar, notifications, launcher, etc.) ──
  programs.noctalia-shell = {
    enable = true;
    # settings = { };  # configure via Noctalia GUI or add nix options later
  };

  # ─── Niri (Wayland compositor) ───────────────────────────────────────────
  programs.niri.settings = let
    noctalia = cmd:
      [ "noctalia-shell" "ipc" "call" ] ++ (pkgs.lib.splitString " " cmd);
  in {
    spawn-at-startup = [
      { command = [ "noctalia-shell" ]; }
    ];

    binds = with config.lib.niri.actions; {
      "Mod+T".action.spawn = [ "kitty" ];
      "Mod+Space".action.spawn = noctalia "launcher toggle";
      "Mod+L".action.spawn = noctalia "lockScreen lock";
      "Mod+Q".action = close-window;
      "XF86AudioRaiseVolume".action.spawn = noctalia "volume increase";
      "XF86AudioLowerVolume".action.spawn = noctalia "volume decrease";
      "XF86AudioMute".action.spawn = noctalia "volume muteOutput";
      "XF86MonBrightnessUp".action.spawn = noctalia "brightness increase";
      "XF86MonBrightnessDown".action.spawn = noctalia "brightness decrease";
    };

    input.keyboard.xkb.layout = "pl";
  };

  # ─── Packages ────────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Terminal
    kitty

    # Editors & dev tools
    neovim
    lazygit

    # Backup (reads old Ubuntu/deja-dup duplicity backups)
    deja-dup

    # Noctalia recommended deps
    brightnessctl
    cliphist
    wl-clipboard
  ];
}
