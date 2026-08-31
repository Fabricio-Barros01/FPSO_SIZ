{
  description = "Projeto Julia";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.julia-bin   # binario oficial; o gerenciador de pacotes do
                             # proprio Julia (Pkg) cuida das dependencias no
                             # Project.toml / Manifest.toml do projeto.

            # Ferramentas de build que alguns pacotes Julia com componente
            # nativo (ex.: os que compilam via BinaryBuilder localmente) pedem:
            pkgs.gcc
            pkgs.gnumake
          ];

          shellHook = ''
            echo "Julia $(julia --version)"
            echo "-> julia --project=.    (ativa o ambiente do projeto)"
            echo "   dentro: ] instantiate (instala deps do Manifest)"
          '';
        };
      });
}
