# This file is a placeholder for flake evaluation.
# The installer generates the real hardware-configuration.nix at install time.
# After installation, commit the generated version to this repo.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Placeholder — overwritten at install time
  boot.initrd.availableKernelModules = [ ];
  boot.kernelModules = [ ];
}
