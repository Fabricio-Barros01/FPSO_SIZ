#!/usr/bin/env julia
#
# build.jl — prepara o ambiente, testa e empacota o FPSO_Siz num executável.
#
#   julia build/build.jl              # tudo: deps, testes, executável, pacote
#   julia build/build.jl deps         # só instala/instancia as dependências
#   julia build/build.jl teste        # só roda os testes (core + interface)
#   julia build/build.jl app          # só gera o executável
#   julia build/build.jl pacote       # só compacta o que já foi gerado
#
# Roda igual no Linux e no Windows. O que ele NÃO faz é compilação cruzada: o
# PackageCompiler gera código para a máquina em que roda, então o artefato de Linux sai
# de uma máquina Linux e o de Windows de uma Windows. Ver build/LEIAME.md.
#
# REGRA DE MANUTENÇÃO: dependência nova de qualquer sprint entra no Project.toml do
# ambiente correspondente (raiz para o core, app/ para a interface) — é isso que mantém
# verdadeira a promessa de que este script continua rodando do zero depois de cada
# sprint.

using Pkg
using Dates
using TOML

const RAIZ  = normpath(joinpath(@__DIR__, ".."))
const APP   = joinpath(RAIZ, "app")
const BUILD = @__DIR__
const OUT   = joinpath(BUILD, "out")

# ---------------------------------------------------------------------------
# Relato de etapas
# ---------------------------------------------------------------------------

"""
    etapa(f, descricao)

Roda `f()`, imprime `✅ descricao` e devolve o resultado; uma `AbstractString` devolvida
sai indentada como detalhe. Em caso de falha imprime `❌`, o erro com backtrace, e
encerra com código 1 — para que o script sirva de portão em CI, não só de conveniência.
"""
function etapa(f::Function, descricao::AbstractString)
    # A linha de progresso só faz sentido onde o `\r` volta ao início da linha. Num log
    # de CI, que não é terminal, ela apareceria duplicada com a linha do resultado.
    interativo = stdout isa Base.TTY
    if interativo
        print("   … ", descricao, "\r")
        flush(stdout)
    end
    try
        resultado = f()
        println("✅ ", descricao, interativo ? " " ^ 8 : "")
        resultado isa AbstractString && println("      ", resultado)
        return resultado
    catch err
        println("❌ ", descricao, interativo ? " " ^ 8 : "")
        println()
        diagnostico_de_sinal(err)
        showerror(stdout, err, catch_backtrace())
        println()
        exit(1)
    end
end

"""
    diagnostico_de_sinal(err)

Traduz "o subprocesso morreu por sinal" antes que o backtrace o esconda.

Isto existe porque já aconteceu: o `create_app` foi morto pelo gerenciador de memória do
sistema no meio da compilação do sysimage, e o que sobrou na tela foi um
`ProcessFailedException` com código 137 — um número que não diz nada a quem só quer o
programa. 137 é 128 + 9 (`SIGKILL`), e num build de sysimage a causa quase certa é falta
de memória. Perder uma tarde relendo backtrace por causa de uma linha ausente é caro
demais.
"""
function diagnostico_de_sinal(err)
    err isa ProcessFailedException || return nothing
    for p in err.procs
        codigo = p.exitcode
        codigo > 128 || continue
        sinal = codigo - 128
        println("   O processo foi morto pelo sistema (código $codigo = 128 + $sinal).")
        if sinal == 9
            println("""
                  SIGKILL durante a compilação quase sempre é falta de memória: o
                  `create_app` reconstrói o sysimage inteiro e é a etapa mais cara do
                  build. Veja o piso de memória e as alternativas em build/LEIAME.md.
                """)
        end
        println()
    end
    return nothing
end

"Como [`etapa`](@ref), mas a falha não derruba o build: imprime `⚠️` e segue."
function aviso(f::Function, descricao::AbstractString)
    try
        r = f()
        println("✅ ", descricao)
        r isa AbstractString && println("      ", r)
        return r
    catch err
        println("⚠️  ", descricao)
        println("      não concluiu: ", sprint(showerror, err))
        return nothing
    end
end

cabecalho(t) = (println(); println("═══ ", t, " ═══"); println())

# ---------------------------------------------------------------------------
# Identidade do artefato
# ---------------------------------------------------------------------------

so() = Sys.iswindows() ? "windows" : Sys.isapple() ? "macos" : "linux"

versao() = get(TOML.parsefile(joinpath(APP, "Project.toml")), "version", "0.0.0")

nome_bundle() = "fpso-siz-$(so())-$(Sys.ARCH)-v$(versao())"

destino() = joinpath(OUT, nome_bundle())

"Nome do executável dentro do bundle."
executavel() = Sys.iswindows() ? "fpso-siz.exe" : "fpso-siz"

# ---------------------------------------------------------------------------
# deps
# ---------------------------------------------------------------------------

"""
    deps()

Instancia os três ambientes: core (raiz), interface (`app/`) e build. São separados de
propósito — o core não conhece a interface, e o compilador não vai para o executável.
"""
function deps()
    cabecalho("FPSO_Siz — dependências")
    println("Julia ", VERSION, "  ·  ", Sys.MACHINE)
    println()

    etapa("core: instancia $(RAIZ)") do
        Pkg.activate(RAIZ; io = devnull)
        Pkg.instantiate(; io = devnull)
        "$(length(Pkg.dependencies())) pacote(s)"
    end

    etapa("interface: instancia $(APP)") do
        Pkg.activate(APP; io = devnull)
        Pkg.instantiate(; io = devnull)
        "$(length(Pkg.dependencies())) pacote(s)"
    end

    etapa("interface: precompila") do
        Pkg.activate(APP; io = devnull)
        Pkg.precompile(; io = devnull)
        nothing
    end

    etapa("build: instancia o PackageCompiler") do
        Pkg.activate(BUILD; io = devnull)
        Pkg.instantiate(; io = devnull)
        nothing
    end
    return nothing
end

# ---------------------------------------------------------------------------
# teste
# ---------------------------------------------------------------------------

"""
    teste()

Testes do core e da interface. É portão: o que não passa não é empacotado — um
executável que sai com a física quebrada é pior do que um build que falhou.
"""
function teste()
    cabecalho("FPSO_Siz — testes")

    etapa("core: 8 arquivos, incluindo o caso-ouro de Alves & Komesu") do
        Pkg.activate(RAIZ; io = devnull)
        Pkg.test("FPSOSiz")
        nothing
    end

    etapa("interface: fumaça (servidor de verdade, headless)") do
        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        run(`$julia --project=$APP $(joinpath(APP, "smoke.jl"))`)
        nothing
    end
    return nothing
end

# ---------------------------------------------------------------------------
# app
# ---------------------------------------------------------------------------

"""
    app()

Gera o executável com o `PackageCompiler.create_app` e monta o bundle ao redor dele.

O `create_app` embarca no sysimage o *código* de todos os pacotes, mas **não** copia os
diretórios de dados deles. Por isso `config/` e `public/` são copiados aqui à mão, para
`share/fpso_siz/`, onde `FPSOSiz.project_root()` os procura a partir de `Sys.BINDIR`.
"""
function app()
    cabecalho("FPSO_Siz — executável")

    dest = destino()
    isdir(dest) && etapa("limpa $(relpath(dest, RAIZ))") do
        rm(dest; recursive = true); nothing
    end
    mkpath(OUT)

    # O `create_app` roda num processo separado, com o ambiente do build ativo. Fazê-lo
    # aqui dentro exigiria ativar `build/` neste processo e carregar o PackageCompiler
    # em tempo de execução, o que traz o problema de *world age*: a função recém-
    # carregada não é visível para o método que a chamou. O subprocesso não tem essa
    # complicação, e ainda isola a memória da compilação do sysimage.
    etapa("create_app (demora: é a compilação do sysimage inteiro)") do
        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        script = """
        using PackageCompiler
        create_app(
            raw"$APP", raw"$dest";
            executables = ["$(replace(executavel(), ".exe" => ""))" => "julia_main"],
            precompile_execution_file = raw"$(joinpath(APP, "precompile", "aquecimento.jl"))",
            include_lazy_artifacts = true,
            incremental = false,
            force = true)
        """
        # `JULIA_NUM_THREADS=1` não é preciosismo: com `incremental = false` o
        # PackageCompiler compila em paralelo, e cada thread carrega sua própria cópia
        # do estado do compilador. Numa máquina de 12 núcleos e 8 GB isso estoura a
        # memória e o `create_app` é morto pelo sistema no meio do sysimage — é o que
        # aconteceu aqui, e é o que o PackageCompiler #778 descreve. Serializar troca
        # tempo de parede, que sobra num build, por memória, que não sobra.
        #
        # `incremental = false` fica como está: é ele que produz um sysimage que não
        # depende do depot da máquina de build, e essa relocabilidade é a razão de ser
        # do Sprint 2 inteiro.
        ambiente = copy(ENV)
        ambiente["JULIA_NUM_THREADS"] = "1"
        ambiente["JULIA_IMAGE_THREADS"] = "1"
        run(setenv(`$julia --project=$BUILD --startup-file=no -e $script`, ambiente))
        nothing
    end

    dados = joinpath(dest, "share", "fpso_siz")
    etapa("copia config/ e public/ para share/fpso_siz/") do
        mkpath(dados)
        cp(joinpath(RAIZ, "config"), joinpath(dados, "config"); force = true)
        cp(joinpath(APP, "public"), joinpath(dados, "public"); force = true)
        "$(length(readdir(joinpath(dados, "config")))) item(ns) em config/, " *
        "$(length(readdir(joinpath(dados, "public")))) em public/"
    end

    etapa("escreve os lançadores e o LEIAME") do
        escrever_lancadores(dest)
        write(joinpath(dest, "LEIAME.txt"), leiame())
        nothing
    end

    etapa("confere que o bundle roda de fora do projeto") do
        conferir(dest)
    end

    println()
    println("Bundle: ", dest)
    println("Tamanho: ", tamanho_legivel(dest))
    return dest
end

"""
    escrever_lancadores(dest)

Um arquivo para clicar duas vezes, em cada sistema. O usuário-alvo é um engenheiro de
processo: ele não deveria precisar de um terminal para dimensionar um vaso.
"""
function escrever_lancadores(dest)
    sh = """
    #!/usr/bin/env bash
    # FPSO_Siz — atalho de clique duplo. Abre a interface no navegador padrão.
    cd "\$(dirname "\${BASH_SOURCE[0]}")"
    ./bin/fpso-siz "\$@" || {
        echo
        read -rp "O programa encerrou com erro. Pressione Enter para fechar."
    }
    """
    caminho_sh = joinpath(dest, "FPSO_Siz.sh")
    write(caminho_sh, sh)
    Sys.iswindows() || chmod(caminho_sh, 0o755)

    bat = """
    @echo off
    rem FPSO_Siz — atalho de clique duplo. Abre a interface no navegador padrao.
    cd /d "%~dp0"
    bin\\fpso-siz.exe %*
    if errorlevel 1 (
      echo.
      echo O programa encerrou com erro.
      pause
    )
    """
    write(joinpath(dest, "FPSO_Siz.bat"), replace(bat, "\n" => "\r\n"))
    return nothing
end

"""
    conferir(dest)

Roda o executável recém-gerado **de fora do diretório do projeto e sem depot Julia
visível**, em modo lote. É o teste que realmente decide se o bundle é relocável: se
algum caminho tivesse ficado congelado na precompilação, é aqui que ele aparece.
"""
function conferir(dest)
    exe = joinpath(dest, "bin", executavel())
    isfile(exe) || error("o executável não foi gerado: $exe")

    saida = mktempdir()
    ambiente = copy(ENV)
    delete!(ambiente, "FPSOSIZ_RAIZ")
    delete!(ambiente, "FPSOSIZ_PUBLIC")
    delete!(ambiente, "JULIA_PROJECT")
    ambiente["JULIA_DEPOT_PATH"] = joinpath(saida, "depot-inexistente")
    ambiente["FPSOSIZ_SAIDA"] = saida

    cd(tempdir()) do
        run(setenv(`$exe --lote`, ambiente))
    end

    arquivos = readdir(saida)
    for sufixo in ("_varredura.csv", "_memorial.txt",
                   "_vaso.svg", "_corte.svg", "_leff.svg", "_sr.svg")
        any(f -> endswith(f, sufixo), arquivos) ||
            error("o bundle rodou mas não gravou $sufixo — algum caminho não é relocável")
    end
    return "gravou $(length(arquivos)) arquivo(s) a partir de $(tempdir())"
end

# ---------------------------------------------------------------------------
# pacote
# ---------------------------------------------------------------------------

"""
    pacote()

Compacta o bundle: `.tar.gz` no Unix, `.zip` no Windows — o formato que cada sistema
abre com duplo clique, sem instalar nada.
"""
function pacote()
    cabecalho("FPSO_Siz — pacote")
    dest = destino()
    isdir(dest) || error("nada para empacotar: rode `julia build/build.jl app` antes.")

    if Sys.iswindows()
        arquivo = dest * ".zip"
        etapa("zip $(basename(arquivo))") do
            rm(arquivo; force = true)
            run(`powershell -NoProfile -Command "Compress-Archive -Path '$dest' -DestinationPath '$arquivo' -Force"`)
            nothing
        end
    else
        arquivo = dest * ".tar.gz"
        etapa("tar.gz $(basename(arquivo))") do
            rm(arquivo; force = true)
            run(`tar -C $OUT -czf $arquivo $(basename(dest))`)
            nothing
        end
    end

    println()
    println("Pacote: ", arquivo, "  (", tamanho_legivel(arquivo), ")")
    return arquivo
end

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

function tamanho_bytes(caminho)
    isfile(caminho) && return filesize(caminho)
    total = 0
    for (dir, _, arquivos) in walkdir(caminho), f in arquivos
        total += try filesize(joinpath(dir, f)) catch; 0 end
    end
    return total
end

function tamanho_legivel(caminho)
    b = tamanho_bytes(caminho)
    for (lim, un) in ((1024^3, "GB"), (1024^2, "MB"), (1024, "kB"))
        b >= lim && return string(round(b / lim; digits = 1), " ", un)
    end
    return string(b, " B")
end

leiame() = """
FPSO_Siz — dimensionamento de separadores trifásicos horizontais
Método semiempírico de Stewart & Arnold (2008)
SENAI CETIQT — versão $(versao()), gerada em $(Dates.format(Dates.now(), "dd/mm/yyyy"))

COMO USAR
---------
Linux/macOS:  ./FPSO_Siz.sh
Windows:      clique duas vezes em FPSO_Siz.bat

A interface abre no seu navegador padrão. Nada precisa ser instalado — nem o Julia.
Para encerrar, feche a janela do terminal que abriu junto.

LINHA DE COMANDO
----------------
  bin/$(executavel()) --lote            dimensiona sem abrir o navegador
  bin/$(executavel()) --porta 9000      usa outra porta
  bin/$(executavel()) --sem-navegador   sobe o servidor sem abrir o navegador
  bin/$(executavel()) --ajuda           todas as opções

ONDE FICAM OS ARQUIVOS
----------------------
Entradas:  share/fpso_siz/config/       (correntes, constantes do método, casos)
Saídas:    share/fpso_siz/saida/        (CSV, memorial e figuras SVG)

Se esta pasta não for gravável — instalação em /opt ou em C:\\Program Files —, as
saídas vão para a sua pasta pessoal, e o programa informa o caminho ao abrir.

AVISOS
------
O executável não é assinado digitalmente. No Windows o SmartScreen pode pedir
confirmação ("Mais informações" → "Executar assim mesmo") e alguns antivírus podem
sinalizar programas Julia empacotados. É esperado.

O servidor escuta apenas em 127.0.0.1 — nada é exposto na rede.
"""

# ---------------------------------------------------------------------------
# Despacho
# ---------------------------------------------------------------------------

function main(argv)
    comando = isempty(argv) ? "tudo" : argv[1]
    t0 = time()

    if comando == "deps"
        deps()
    elseif comando == "teste"
        teste()
    elseif comando == "app"
        app()
    elseif comando == "pacote"
        pacote()
    elseif comando == "tudo"
        deps(); teste(); app(); pacote()
    else
        println("comando desconhecido: ", comando)
        println("use: deps | teste | app | pacote | tudo")
        return 1
    end

    println()
    println("Concluído em ", round((time() - t0) / 60; digits = 1), " min.")
    return 0
end

# A forma `cond && exit(...)` não serve aqui: `@__FILE__` é uma macro e engoliria o
# `&& exit(...)` como argumento, o que é erro de sintaxe.
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
