{
  description = "Native Nix package and NixOS module for Logchef";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system: {
        default = self.packages.${system}.logchef;
        logchef = nixpkgs.legacyPackages.${system}.callPackage ./package.nix { };
      });

      nixosModules.default = import ./module.nix;

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          moduleEvaluation = import ./tests/module-evaluation.nix {
            inherit (nixpkgs) lib;
            inherit pkgs;
            module = self.nixosModules.default;
            package = self.packages.${system}.logchef;
          };
        in
        {
          inherit moduleEvaluation;
          package = self.packages.${system}.logchef;
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          vm = import ./tests/vm.nix {
            inherit pkgs;
            module = self.nixosModules.default;
            package = self.packages.${system}.logchef;
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              bun
              go_1_26
              just
              nix-update
              nixfmt-tree
            ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
