{
  description = "GreenBoost — 3-Tier GPU Memory Extension for Linux (NixOS package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];
    in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      in
      {
        packages = {
          greenboost-module = pkgs.callPackage ./pkgs/greenboost-module.nix { };
          greenboost-shim   = pkgs.callPackage ./pkgs/greenboost-shim.nix { };
        };

        # Default package is the shim (most users want both via the NixOS module)
        packages.default = self.packages.${system}.greenboost-shim;
      }
    ) // {
      # NixOS module — import this in your configuration.nix
      nixosModules.default = import ./modules/greenboost.nix self;
      nixosModules.greenboost = self.nixosModules.default;
    };
}
