{
  description = "ZeroClaw NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      lib = nixpkgs.lib;
      modules = {
        default = import ./nix/module.nix;
        zeroclaw = import ./nix/module.nix;
      };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        inherit modules;
        checks = {
          test-module = import ./tests { inherit pkgs modules; };
        };
      }
    ) // {
      nixosModules = modules;
    };
}
