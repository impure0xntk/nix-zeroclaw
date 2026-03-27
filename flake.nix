{
  description = "ZeroClaw NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        modules = {
          default = self.nixosModules.zeroclaw;
          zeroclaw = import ./nix/module.nix self;
        };
      in
      {
        nixosModules = modules;

        checks = {
          test-module = import ./tests { inherit pkgs modules; };
        };
      }
    );
}