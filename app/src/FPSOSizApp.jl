"""
    FPSOSizApp

Interface do FPSO_Siz: um servidor HTTP local que serve a tela ao navegador.

    julia --project=app -e 'using FPSOSizApp; FPSOSizApp.main()'   # abre o navegador
    julia --project=app -e 'using FPSOSizApp; FPSOSizApp.main(["--lote"])'

Empacotado, o mesmo programa vira um executável:

    ./FPSO_Siz.sh            # ou FPSO_Siz.bat no Windows
    bin/fpso-siz --lote

## Por que navegador em vez de janela nativa

A versão anterior desenhava com GLMakie. Numa máquina sem OpenGL 3.3 — VM, sessão
remota, driver sem aceleração — o GLMakie falha **na precompilação**, então o programa
morria antes de chegar à física; e o GLFW que o Julia baixa é um binário pré-compilado
que procura driver em `/usr/lib/dri`, o que o torna impossível de empacotar de forma
relocável. Todo computador já tem navegador; nenhum precisa de driver gráfico para
mostrar SVG.

## `import FPSOSiz`, nunca `using`

`FPSOSiz` exporta `label` e `parameters`; o `Genie.Renderer.Html` exporta `label`
também. Com `using` nos dois o nome fica ambíguo e o Julia lança `UndefVarError` — mas
só **no instante em que a linha roda**, dentro de um handler, com o servidor no ar e a
página devolvendo HTTP 200. Qualificar todas as travessias app → core custa alguns
caracteres e torna a classe de bug impossível.
"""
module FPSOSizApp

using Base64          # a marca do emitente embutida no memorial exportado
using Dates
using Printf

import FPSOSiz
import Genie
import HTTP
import JSON3
import Logging
import Sockets

include("formato.jl")

include("desenho/svg.jl")
include("desenho/geometria.jl")
include("desenho/vaso.jl")
# Os esquemas dos dois equipamentos que não são vasos — diagramas, não desenhos de escala.
include("desenho/linha.jl")
include("desenho/graficos.jl")

include("state.jl")
# Depois de `state.jl`: o dispatcher de figuras despacha no método E recebe o `AppState`.
include("desenho/figuras.jl")
include("report.jl")
include("api.jl")
# O memorial de cálculo documental. Depois de `api.jl` (usa `campos_resultado`, a mesma
# fonte do cartão da tela) e de `figuras.jl` (reaproveita as SVG), antes de `server.jl`,
# que o serve. A infra da folha A4 não sabe qual equipamento está documentando: o
# conteúdo vem do `FPSOSiz.memorial_spec` do método.
include("memorial/mathml.jl")
include("memorial/documento.jl")
include("memorial/folhas.jl")
# A tela dinâmica (Song 2023) — subapp isolado: não passa pelo AppState nem por api.jl.
# Depois de graficos.jl (usa svg_serie_temporal) e antes de server.jl (que a serve).
include("dinamico.jl")
include("server.jl")

export main, julia_main

# O texto NÃO cita um equipamento nem um método. Dizia "separadores trifásicos
# horizontais / Stewart & Arnold (2008)" desde o Sprint 0, quando era verdade; desde o
# menu do Sprint 6 são seis aplicações, e a citação do método é por equipamento — ela
# vive em `method_reference`, declarada no TOML de cada método, e sai no memorial.
const LEMA = "FPSO_Siz — dimensionamento de equipamentos de processamento primário"

const USO = """
$LEMA

  fpso-siz [opções]

  --lote               não abre a interface: dimensiona, grava CSV, memorial e SVG
  --porta N            porta do servidor (padrão 8000; ocupada, escolhe outra)
  --sem-navegador      sobe o servidor mas não abre o navegador
  --caso ARQUIVO       abre já com este conjunto de casos (padrão: começa em branco)
  --ajuda              mostra esta mensagem
"""

"Lê os argumentos de linha de comando. Opção desconhecida vira aviso, não erro fatal."
function ler_argumentos(argv)
    # `caso` vazio = a interface abre no menu, e cada aplicação começa em branco. Só
    # quem passa `--caso` explicitamente entra já com um arquivo carregado.
    opts = (lote = false, porta = 8000, navegador = true, caso = "", ajuda = false)
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a == "--lote"
            opts = merge(opts, (lote = true,))
        elseif a == "--sem-navegador"
            opts = merge(opts, (navegador = false,))
        elseif a in ("--ajuda", "--help", "-h")
            opts = merge(opts, (ajuda = true,))
        elseif a == "--porta" && i < length(argv)
            p = tryparse(Int, argv[i+1])
            p === nothing ? @warn("porta inválida, usando a padrão", valor = argv[i+1]) :
                            (opts = merge(opts, (porta = p,)))
            i += 1
        elseif a == "--caso" && i < length(argv)
            opts = merge(opts, (caso = argv[i+1],))
            i += 1
        else
            @warn "opção desconhecida, ignorada" opcao = a
        end
        i += 1
    end
    return opts
end

"""
    main(argv = ARGS) -> Int

`0` = a interface subiu e encerrou normalmente; `1` = não foi possível servir e o
programa caiu para o modo lote; `2` = nem o lote conseguiu dimensionar.

Nunca lança para o chamador: um executável que aborta com stacktrace não serve para
quem só quer dimensionar um vaso.
"""
function main(argv::Vector{String} = ARGS)
    opts = ler_argumentos(argv)
    opts.ajuda && (print(USO); return 0)

    ARQUIVO_CASOS[] = opts.caso
    opts.lote && return modo_lote(; case_file = opts.caso)

    try
        servir(; porta = opts.porta, abrir = opts.navegador)
        return 0
    catch err
        err isa InterruptException && return 0
        @warn """
        Não foi possível servir a interface. Caindo para o modo lote (CSV, memorial e
        SVG em $(FPSOSiz.dir_saida())).
        """ exception = (err, catch_backtrace())
        return modo_lote(; case_file = opts.caso) == 0 ? 1 : 2
    end
end

"""
    modo_lote(; case_file) -> Int

Sem interface: dimensiona, imprime o resultado e grava CSV, memorial e as figuras.
"""
function modo_lote(; case_file::AbstractString = "")
    # Sem interface não há de onde escolher um arquivo, então o lote mantém o exemplo
    # de referência como default — é o que faz `fpso-siz --lote` produzir algo útil.
    st = AppState(; case_file = isempty(case_file) ? "exemplo_alves_komesu.toml" : case_file)
    dimensionar!(st)

    println("FPSO_Siz — modo lote")
    println(repeat("=", 72))

    r = st.resultado
    if r === nothing || !r.feasible
        println("Não foi possível dimensionar: ", st.status)
        return 2
    end

    @printf("%d caso(s) de canto avaliado(s)\n", length(r.case_names))
    # Os campos do resultado são os que o método declara — não uma linha de printf com
    # os nomes do vaso, que o lote de uma bomba teria de reescrever. Um por linha, e não
    # todos numa só: a quantidade agora varia com o método, e uma linha de 200 colunas
    # no terminal se lê pior que oito de 40.
    for f in FPSOSiz.result_fields(st.metodo, r)
        v = f.value isa AbstractString ? f.value :
            isfinite(f.value) ? Formato.num(f.value, f.digits) : "—"
        println(rstrip(@sprintf("  %-32s %s %s", f.label, v, f.unit)))
    end
    println(FPSOSiz.governing_summary(st.metodo, r))
    println()

    exportar!(st)
    println(st.status)
    return st.status_ok ? 0 : 2
end

"""
    julia_main() -> Cint

Ponto de entrada do executável gerado pelo `PackageCompiler.create_app`. Assinatura
fixada pelo PackageCompiler: sem argumentos, devolvendo `Cint`; os argumentos chegam
por `ARGS`.
"""
function julia_main()::Cint
    try
        return Cint(main(ARGS))
    catch err
        err isa InterruptException && return Cint(0)
        @error "erro fatal" exception = (err, catch_backtrace())
        return Cint(2)
    end
end

end # module FPSOSizApp
