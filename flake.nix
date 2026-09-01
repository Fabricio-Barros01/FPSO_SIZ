{
  description = "FPSO_Siz - dimensionamento de separadores (Julia)";

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

            # O PackageCompiler LINKA o sysimage: precisa de compilador e linker
            # de verdade, nao so para instalar pacotes.
            pkgs.gcc
            pkgs.gnumake

            pkgs.curl        # usado pelo build/bootstrap.sh

            # SO PARA `node --check` em app/smoke.jl: um erro de sintaxe no app.js
            # nao aparece em lugar nenhum do lado do Julia - a pagina e servida com
            # status 200 e para em "Carregando...". Nada do programa roda em Node; o
            # teste que o usa se PULA quando o node nao esta instalado, entao o
            # build/bootstrap.sh continua rodando numa maquina sem ele.
            pkgs.nodejs_22
          ];

          shellHook = ''
            # ----------------------------------------------------------------
            # Nota historica: o que sumiu daqui, e por que
            # ----------------------------------------------------------------
            # Ate a migracao para o Genie, este arquivo carregava ~55 linhas de
            # LD_LIBRARY_PATH, LIBGL_DRIVERS_PATH e __GLX_VENDOR_LIBRARY_NAME
            # apontando para a pilha OpenGL do sistema. Era o preco do GLMakie:
            # ele usa GLFW, que o Julia baixa como binario JLL pre-compilado,
            # que por sua vez procura driver em /usr/lib/dri - caminho que nao
            # existe no NixOS, que nao segue o FHS.
            #
            # A interface agora e uma pagina servida ao navegador, desenhada em
            # SVG gerado em Julia. Nao ha OpenGL no caminho, entao nao ha o que
            # apontar. E foi essa mesma nao-relocabilidade do JLL do GLFW que
            # tornava impossivel empacotar o programa com o PackageCompiler.
            #
            # ATENCAO ao distribuir: um bundle gerado DENTRO deste shell aponta
            # para a glibc do /nix/store e nao roda num Ubuntu comum. Para o
            # artefato distribuivel, use um container julia:1.12 ou o runner do
            # GitHub Actions. Ver build/LEIAME.md.

            echo "Julia $(julia --version)"
            echo ""
            echo "-> julia --project=.        (core, sem interface)"
            echo "   dentro: ] instantiate    (instala deps do Manifest)"
            echo "   julia --project=. -e 'using Pkg; Pkg.test()'"
            echo ""
            echo "-> julia --project=app -e 'using FPSOSizApp; FPSOSizApp.main()'"
            echo "        abre a interface no navegador (127.0.0.1)"
            echo "   ... FPSOSizApp.main([\"--lote\"])   sem navegador: CSV + memorial + SVG"
            echo "-> julia --project=app app/smoke.jl   teste da interface, headless"
            echo ""
            echo "-> ./build/bootstrap.sh     executavel autocontido em build/out/"
            echo "   julia build/build.jl deps|teste|app|pacote"
          '';
        };
      });
}
