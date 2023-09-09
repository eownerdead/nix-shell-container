{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      rec {
        formatter = pkgs.nixpkgs-fmt;

        overlays.default = final: prev: {
          nixShellContainer = lib;
        };

        devShells = {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixpkgs-fmt
              statix
              bubblewrap
            ];
          };

          container = lib.mkBwrapContainer {
            drv = devShells.default;
          };

          hello-test = lib.mkBwrapContainer {
            drv = pkgs.hello;
          };
        };

        lib = import ./containerize.nix { inherit pkgs; };
      });
}
