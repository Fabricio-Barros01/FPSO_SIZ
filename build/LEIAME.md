# build/ — como gerar o executável

O objetivo é um programa que o usuário descompacta e roda: sem instalar Julia, sem
`Pkg.instantiate`, sem placa de vídeo.

```
./build/bootstrap.sh                 # Linux/macOS — instala o Julia se faltar
.\build\bootstrap.ps1                # Windows
julia build/build.jl deps|teste|app|pacote|tudo
```

Saída em `build/out/fpso-siz-<so>-<arch>-v<versão>/`, mais o `.tar.gz` (ou `.zip`).

## As etapas

| Comando | O que faz |
|---|---|
| `deps` | Instancia os três ambientes: core (raiz), interface (`app/`) e build. |
| `teste` | `Pkg.test("FPSOSiz")` + `app/smoke.jl`. **Portão**: o que não passa não é empacotado. |
| `app` | `PackageCompiler.create_app`, copia `config/` e `public/`, escreve os lançadores, e confere que o bundle roda relocado. |
| `pacote` | `.tar.gz` no Unix, `.zip` no Windows. |

## Layout do bundle

```
fpso-siz-linux-x86_64-v0.1.0/
  FPSO_Siz.sh · FPSO_Siz.bat     atalho de clique duplo
  LEIAME.txt
  bin/fpso-siz                   o executável
  lib/  share/julia/             sysimage e artefatos (do PackageCompiler)
  share/fpso_siz/config/         entradas: correntes, constantes, casos
  share/fpso_siz/public/         a interface (HTML, CSS, JS, logo)
  share/fpso_siz/saida/          CSV, memorial e SVG (criado no primeiro uso)
```

`share/fpso_siz/` é achado em tempo de execução por `FPSOSiz.project_root()`, a partir
de `Sys.BINDIR` — é isso que torna o bundle relocável. Ver `src/config.jl`.

## Duas armadilhas que este build já evita

**1. Caminho congelado na precompilação.** `const RAIZ = joinpath(@__DIR__, "..")`
resolveria no momento do build e apontaria para o `~/.julia` da máquina que compilou.
`src/config.jl` resolve em runtime, e `build.jl` confere isso rodando o executável a
partir de `/tmp`, com `JULIA_DEPOT_PATH` inexistente: se algum caminho tivesse ficado
para trás, a etapa `app` falha ali.

**2. Diretório-fonte de pacote.** O `create_app` embarca o *código* das dependências no
sysimage, mas não copia os diretórios de dados delas. Por isso a interface não usa
`Genie.Assets` nem Stipple, que resolvem os próprios arquivos com `@__DIR__` e
`Base.pkgdir(Genie)`. Ver a nota no topo de `app/src/server.jl`.

**3. Memória na compilação do sysimage.** A etapa `app` é, de longe, a mais cara do
build, e já foi morta pelo gerenciador de memória do sistema no meio dela — o sintoma é
o script terminar com código **137** (= 128 + 9, `SIGKILL`) deixando em `build/out/` um
bundle pela metade: `bin/` só com `julia`, sem `share/fpso_siz/`, sem lançadores e sem
tarball.

A causa é o paralelismo: com `incremental = false` o PackageCompiler compila em várias
threads, e cada uma carrega sua própria cópia do estado do compilador
([PackageCompiler #778](https://github.com/JuliaLang/PackageCompiler.jl/issues/778),
[#1031](https://github.com/JuliaLang/PackageCompiler.jl/issues/1031)). Por isso
`build.jl` roda o `create_app` com `JULIA_NUM_THREADS=1`: troca tempo de parede, que
sobra num build, por memória, que não sobra.

**Piso observado:** 8 GB de RAM **com swap** basta, serializado. Sem swap, ou em paralelo,
não basta. Relatos da comunidade convergem para 16 GB como o valor confortável — se o
build morrer com 137 mesmo depois desta mudança, é aí que está o limite, e o caminho é
o container ou o runner de CI da seção abaixo.

## Não há compilação cruzada

O PackageCompiler gera código para a máquina em que roda. O artefato de Linux sai de
uma máquina Linux, o de Windows de uma Windows.

**No NixOS, atenção:** um bundle gerado dentro do `nix develop` linka contra a glibc do
`/nix/store` e **não roda num Ubuntu comum**. O shell Nix serve ao desenvolvimento; para
o artefato distribuível use um container `julia:1.12` ou um runner do GitHub Actions:

```yaml
# .github/workflows/build.yml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest]
steps:
  - uses: actions/checkout@v4
  - uses: julia-actions/setup-julia@v2
    with: { version: '1.12' }
  - run: julia build/build.jl tudo
  - uses: actions/upload-artifact@v4
    with: { name: fpso-siz-${{ matrix.os }}, path: build/out/*.tar.gz build/out/*.zip }
```

## Tamanho e assinatura

O bundle passa de 500 MB descompactado (o sysimage do Julia 1.12 é grande); comprimido
fica na casa das centenas de megabytes. `filter_stdlibs = true` encolheria bastante, mas
quebra com facilidade quando uma dependência carrega uma stdlib por reflexão — não
usamos.

O executável não é assinado. No Windows o SmartScreen pede confirmação e alguns
antivírus sinalizam programas Julia empacotados; está anotado no `LEIAME.txt` do bundle.
