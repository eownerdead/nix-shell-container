# Nix Shell Container
[`guix environment --container`](https://guix.gnu.org/manual/devel/en/html_node/Invoking-guix-environment.html#index-container-2) equivalent in nix.\
Most codes were ~~stolen~~ taken from
[`streamNixShellImage`](https://github.com/NixOS/nixpkgs/blob/9652a97d9738d3e65cf33c0bc24429e495a7868f/pkgs/build-support/docker/default.nix#L1052-L1221)
and [`build-fhsenv-bubblewrap`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/build-fhsenv-bubblewrap/default.nix).\
All the ideas were ~~stolen~~ taken from [here](https://discourse.nixos.org/t/guix-environment-container-equivalent/1511).

# Acknowledgements
* [Nixpkgs](https://github.com/NixOS/nixpkgs)
* [Bubblewrap](https://github.com/containers/bubblewrap)
* [Guix](https://guix.gnu.org)
