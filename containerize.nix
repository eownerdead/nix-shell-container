{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
}:
{
  # https://github.com/NixOS/nixpkgs/blob/9652a97d9738d3e65cf33c0bc24429e495a7868f/pkgs/build-support/docker/default.nix#L1052-L1221
  mkBwrapContainer =
    {
      # The derivation whose environment this container should be based on
      drv
    , # Container name
      name ? "${drv.name}-container"
    , unshareUser ? true
    , unshareIpc ? true
    , unsharePid ? true
    , unshareNet ? false
    , unshareUts ? true
    , unshareCgroup ? true
    , dieWithParent ? true
    , # The home directory of the user
      homeDirectory ? "/build"
    , clearenv ? true
    , # The path to the bash binary to use as the shell. See `NIX_BUILD_SHELL` in `man nix-shell`
      shell ? "${pkgs.bashInteractive}/bin/bash"
    }:
      assert lib.assertMsg (! (drv.drvAttrs.__structuredAttrs or false))
        "mkContainer: Does not work with the derivation ${drv.name} because it uses __structuredAttrs";
      let
        builder = pkgs.writeShellScriptBin "buildDerivation" ''
          exec ${lib.escapeShellArg (stringValue drv.drvAttrs.builder)} ${lib.escapeShellArgs (map stringValue drv.drvAttrs.args)}
        '';

        staticPath = "${dirOf shell}:${lib.makeBinPath [ builder ]}";

        rcfile = pkgs.writeText "${name}-rc" ''
          unset PATH
          dontAddDisableDepTrack=1
          # TODO: https://github.com/NixOS/nix/blob/2.8.0/src/nix-build/nix-build.cc#L506
          [ -e $stdenv/setup ] && source $stdenv/setup
          PATH=${staticPath}:"$PATH"
          SHELL=${lib.escapeShellArg shell}
          BASH=${lib.escapeShellArg shell}
          set +e
          [ -n "$PS1" -a -z "$NIX_SHELL_PRESERVE_PROMPT" ] && PS1='\n\[\033[1;32m\][nix-shell:\w]\$\[\033[0m\] '
          if [ "$(type -t runHook)" = function ]; then
            runHook shellHook
          fi
          unset NIX_ENFORCE_PURITY
          shopt -u nullglob
          shopt -s execfail
        '';

        # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/globals.hh#L464-L465
        sandboxBuildDir = "/build";

        # This function closely mirrors what this Nix code does:
        # https://github.com/NixOS/nix/blob/2.8.0/src/libexpr/primops.cc#L1102
        # https://github.com/NixOS/nix/blob/2.8.0/src/libexpr/eval.cc#L1981-L2036
        stringValue = value:
          # We can't just use `toString` on all derivation attributes because that
          # would not put path literals in the closure. So we explicitly copy
          # those into the store here
          if builtins.typeOf value == "path" then "${value}"
          else if builtins.typeOf value == "list" then toString (map stringValue value)
          else toString value;

        drvEnv = lib.mapAttrs'
          (name: value:
            let str = stringValue value;
            in if lib.elem name (drv.drvAttrs.passAsFile or [ ])
            then lib.nameValuePair "${name}Path" (lib.writeText "pass-as-text-${name}" str)
            else lib.nameValuePair name str
          )
          drv.drvAttrs //
        # A mapping from output name to the nix store path where they should end up
        # https://github.com/NixOS/nix/blob/2.8.0/src/libexpr/primops.cc#L1253
        lib.genAttrs drv.outputs (output: builtins.unsafeDiscardStringContext drv.${output}.outPath);

        envVars = {

          # Root certificates for internet access
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1027-L1030
          # PATH = "/path-not-set";
          # Allows calling bash and `buildDerivation` as the Cmd
          PATH = staticPath;

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1032-L1038
          HOME = homeDirectory;

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1040-L1044
          NIX_STORE = builtins.storeDir;

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1046-L1047
          # TODO: Make configurable?
          NIX_BUILD_CORES = "1";

        } // drvEnv // {

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1008-L1010
          NIX_BUILD_TOP = sandboxBuildDir;

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1012-L1013
          TMPDIR = sandboxBuildDir;
          TEMPDIR = sandboxBuildDir;
          TMP = sandboxBuildDir;
          TEMP = sandboxBuildDir;

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1015-L1019
          PWD = sandboxBuildDir;

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1071-L1074
          # We don't set it here because the output here isn't handled in any special way
          # NIX_LOG_FD = "2";

          # https://github.com/NixOS/nix/blob/2.8.0/src/libstore/build/local-derivation-goal.cc#L1076-L1077
          TERM = "xterm-256color";
        };

        setenv =
          name: value: "  --setenv ${name} ${lib.strings.escapeShellArg value}";

        env =
          lib.strings.concatStringsSep "\n" (lib.mapAttrsToList setenv envVars);

        bwrapenv = pkgs.writeShellScript "${name}-bwrap" ''
          cmd=(
            ${pkgs.bubblewrap}/bin/bwrap
            --proc /proc
            --dev /dev
            --tmpfs /tmp
            --chdir "$(pwd)"
            ${lib.optionalString unshareUser "--unshare-user"}
            ${lib.optionalString unshareIpc "--unshare-ipc"}
            ${lib.optionalString unsharePid "--unshare-pid"}
            ${lib.optionalString unshareNet "--unshare-net"}
            ${lib.optionalString unshareUts "--unshare-uts"}
            ${lib.optionalString unshareCgroup "--unshare-cgroup"}
            ${lib.optionalString dieWithParent "--die-with-parent"}
            ${lib.optionalString clearenv "--clearenv"}
            ${env}
            --ro-bind /nix /nix
            --dir /var
            --symlink ../tmp var/tmp
            --symlink ${pkgs.coreutils}/bin/env usr/bin
            --symlink ${shell} bin/sh
            --dir /run/user/$(id -u)
            --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)"
            --dir /build
            --bind "$(pwd)" "$(pwd)"
            ${drv.stdenv.shell}
            --rcfile ${rcfile}
          )
          exec "''${cmd[@]}"
        '';
      in
      pkgs.mkShell {
        shellHook = ''
          exec ${bwrapenv}
        '';
      };
}
