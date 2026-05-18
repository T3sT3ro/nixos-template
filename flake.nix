{
  description = "NixOS system";

  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
      "https://niri.cachix.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, home-manager, niri, noctalia, ... }@inputs: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    settings = import ./settings.nix;
  in {
    # ─── NixOS system configuration ────────────────────────────────────────
    nixosConfigurations.${settings.hostname} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs settings; };
      modules = [
        disko.nixosModules.disko
        ./disko.nix
        ./hardware-configuration.nix
        ./configuration.nix
        niri.nixosModules.niri
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs settings; };
          home-manager.users.${settings.username} = import ./home.nix;
        }
      ];
    };

    # ─── Installer app ─────────────────────────────────────────────────────
    # Usage from live USB:
    #   sudo nix run github:YOUR_USER/nixos-config
    apps.${system}.default = {
      type = "app";
      program = let
        installer = pkgs.writeShellScriptBin "nixos-installer" ''
          export FLAKE_DIR="${./.}"
          exec ${pkgs.bash}/bin/bash ${./install.sh}
        '';
      in "${installer}/bin/nixos-installer";
    };
  };
}
