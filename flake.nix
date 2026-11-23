{
  description = "sidekick.hx: send files and lines from Helix to AI agents in tmux or herdr-app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-26.05";
    # Helix fork with the Steel plugin system (helix-editor/helix#8675)
    helix = {
      url = "github:mattwparas/helix/steel-event-system";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, helix }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f system (
            import nixpkgs {
              inherit system;
              # claude-code is unfree.
              config.allowUnfree = true;
            }
          )
        );
    in
    {
      # nix run .#demo, from the repository root, records demo/demo.gif.
      apps = forAllSystems (
        system: pkgs:
        let
          demo = pkgs.writeShellApplication {
            name = "sidekick-demo";
            runtimeInputs = [
              (helix.packages.${system}.default.overrideAttrs { cargoBuildFeatures = [ "steel" ]; })
              pkgs.bashInteractive
              pkgs.claude-code
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.procps
              pkgs.tmux
              pkgs.vhs
            ];
            # Without the recorder's PATH, no herdr-app terminals of theirs show up in the picker.
            inheritPath = false;
            text = ''
              export SIDEKICK_SRC=${self}
              ${builtins.readFile ./demo/record.sh}
            '';
          };
        in
        {
          demo = {
            type = "app";
            program = pkgs.lib.getExe demo;
          };
        }
      );
    };
}
