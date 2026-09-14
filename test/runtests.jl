using Test
using TOML
using FPSOSiz

# Filtro por ARGS: `julia test/runtests.jl fisica arquitetura` roda só os grupos cujo
# nome casa (substring, minúsculas) com algum argumento. Sem argumentos, roda a suíte
# inteira. O laço de desenvolvimento paga só pelo que está mexendo; o CI continua rodando
# tudo (sem ARGS).
const _FILTRO = lowercase.(ARGS)
_quer(nome) = isempty(_FILTRO) || any(a -> occursin(a, lowercase(nome)), _FILTRO)

"Roda um grupo de testes se o filtro o pedir. `include` corre no módulo do teste (Main)."
function grupo(nome::AbstractString, arquivo::AbstractString)
    _quer(nome) || return nothing
    @testset "$nome" begin
        include(joinpath(@__DIR__, arquivo))
    end
    return nothing
end

@testset "FPSOSiz" begin
    # Ordem deliberada: unidades e geometria primeiro (se estas quebram, tudo o mais
    # é ruído), depois a física, depois o caso-ouro, depois o motor de envelope.
    grupo("unidades",           "units.jl")
    grupo("β (Figura 3)",       "beta.jl")
    grupo("arrasto",            "drag.jl")
    grupo("casos",              "cases.jl")
    grupo("caso-ouro 3φ",       "golden_alves_komesu.jl")
    grupo("caso-ouro 2φ",       "golden_knockout.jl")
    grupo("caso-ouro bomba",    "golden_moran.jl")
    grupo("caso-ouro trocador", "golden_saari.jl")
    # Pinch é alvo de energia de uma REDE, não dimensionamento de equipamento. Vem
    # depois do trocador porque é a pergunta seguinte, e antes do envelope porque não
    # depende do motor de varredura — nem o alcança.
    grupo("pinch",              "pinch.jl")
    grupo("caso-ouro pinch",    "golden_kemp.jl")
    grupo("encaixe pinch",      "pinch_encaixe.jl")
    grupo("tratador",           "treater.jl")
    # Bateria de invariantes de física, dirigida pelo registro + o módulo dinâmico (E.4).
    grupo("fisica",             "fisica.jl")
    grupo("envelope",           "envelope.jl")
    grupo("registro",           "registry.jl")
    grupo("arquitetura",        "architecture.jl")
end
