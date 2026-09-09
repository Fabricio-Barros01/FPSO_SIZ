"""
    FPSOSizApp

Interface desktop do FPSO_Siz.

    julia --project=app app/main.jl            # abre a janela
    julia --project=app app/main.jl --lote     # sem janela: CSV, memorial e PNG

## Por que o GLMakie é carregado sob demanda

O módulo depende apenas de `Makie` (a camada agnóstica de backend). O GLMakie —
janela nativa OpenGL — é carregado dentro de [`main`](@ref), num `try`. Isso importa:
numa máquina sem OpenGL 3.3 (VM, sessão remota, driver sem aceleração) o GLMakie
falha já na **precompilação**, não só ao abrir a janela. Se ele estivesse no topo do
módulo, o executável inteiro morreria antes de chegar à física.

Carregando sob demanda, o mesmo binário que abre a janela numa máquina com GPU cai
no [`modo_lote`](@ref) numa sem — dimensiona, grava CSV, memorial e uma figura PNG
via CairoMakie (que renderiza em CPU) — em vez de abortar com stacktrace.

`build_dashboard` só usa `Makie`, então a tela é exatamente a mesma nos dois
caminhos: no lote ela vira PNG em vez de janela.
"""
module FPSOSizApp

using Dates
using Printf
using Makie
using FPSOSiz

include("theme.jl")
using .Theme

include("state.jl")
include("report.jl")
include("views/vessel_draw.jl")
include("views/charts.jl")
include("views/dashboard.jl")

export main, montar, modo_lote

const UUID_GLMAKIE    = Base.UUID("e9467ef8-e4e7-5192-8a1a-b1aee30e663a")
const UUID_CAIROMAKIE = Base.UUID("13f3f980-e62b-5c42-98c6-ff1f3baf88f0")

"""
    carregar_backend(uuid, nome) -> Module

Carrega um backend do Makie em tempo de execução e devolve o **módulo**.

Usa `Base.require` em vez de `@eval Main using X` porque esta última cria a ligação
num world age posterior ao da função que a executa: `getfield(Main, :X)` logo depois
falha com `UndefVarError ... binding may be too new`. `Base.require` devolve o módulo
direto. As chamadas a funções dele continuam precisando de `invokelatest`.
"""
carregar_backend(uuid::Base.UUID, nome::AbstractString) =
    Base.require(Base.PkgId(uuid, String(nome)))

"""
    montar(; case_file) -> (fig, state)

Constrói a figura e o estado, já com um dimensionamento inicial feito. **Não** abre
janela nem exige backend — é este o ponto de entrada que o teste de fumaça headless
exercita.
"""
function montar(; case_file::AbstractString = "exemplo_alves_komesu.toml")
    st = AppState(; case_file)
    dimensionar!(st)
    fig = build_dashboard(st)
    return (fig, st)
end

"""
    main(; case_file, lote) -> Int

`0` = janela aberta e fechada normalmente; `1` = caiu para o modo lote; `2` = nem o
lote conseguiu dimensionar. Nunca lança para o chamador — um executável que aborta
com stacktrace não serve para quem só quer dimensionar um vaso.
"""
function main(; case_file::AbstractString = "exemplo_alves_komesu.toml",
                lote::Bool = false)
    Makie.set_theme!(Theme.tema())
    lote && return modo_lote(; case_file)

    try
        gl = carregar_backend(UUID_GLMAKIE, "GLMakie")
        Base.invokelatest(gl.activate!;
                          title = "FPSO_Siz — Dimensionamento de Separadores",
                          focus_on_show = true)
        fig, _ = montar(; case_file)
        tela = Base.invokelatest(display, fig)
        isinteractive() || Base.invokelatest(Makie.wait, tela)
        return 0
    catch err
        @warn """
        Não foi possível abrir a janela gráfica. Isso normalmente significa que a
        máquina não expõe OpenGL 3.3 — VM, sessão remota ou driver sem aceleração.
        Caindo para o modo lote (CSV + memorial + PNG em saida/).
        """ exception = (err, catch_backtrace())
        return modo_lote(; case_file) == 0 ? 1 : 2
    end
end

"""
    modo_lote(; case_file) -> Int

Sem janela: dimensiona, imprime o resultado, grava CSV e memorial, e renderiza a mesma
tela em PNG com o CairoMakie (que não precisa de GPU).
"""
function modo_lote(; case_file::AbstractString = "exemplo_alves_komesu.toml")
    st = AppState(; case_file)
    dimensionar!(st)

    println("FPSO_Siz — modo lote")
    println(repeat("=", 72))

    r = st.resultado[]
    if r === nothing || !r.feasible
        println("Não foi possível dimensionar: ", st.status[])
        return 2
    end

    @printf("%d caso(s) de canto avaliado(s)\n", length(r.case_names))
    @printf("d = %s mm   Leff = %s m   Lss = %s m   SR = %s   V = %s m³\n",
            Theme.inteiro(r.diameter_mm), Theme.num(r.leff_m), Theme.num(r.lss_m),
            Theme.num(r.sr), Theme.num(r.volume_m3, 0))
    println(governing_summary(r))
    println()

    exportar_csv!(st)
    println(st.status[])

    try
        cairo = carregar_backend(UUID_CAIROMAKIE, "CairoMakie")
        Base.invokelatest(cairo.activate!; type = "png", px_per_unit = 1.5)
        Makie.set_theme!(Theme.tema())
        fig = build_dashboard(st)
        png = joinpath(dir_saida(), "fpso_siz_$(carimbo()).png")
        Base.invokelatest(Makie.save, png, fig)
        println("Figura:   ", png)
    catch err
        @warn "Não foi possível renderizar a figura PNG" exception = err
    end
    return 0
end

end # module FPSOSizApp

# Executado como script: julia --project=app app/main.jl [--lote]
if abspath(PROGRAM_FILE) == @__FILE__
    exit(FPSOSizApp.main(; lote = "--lote" in ARGS))
end
