"""
`test/qualidade.jl` — homogeneidade dimensional (E.5) e ferramentas de qualidade (G/H).

Cada bloco é **guardado** pelo flag de disponibilidade: só roda se a ferramenta estiver
instalada. `Pkg.test()` a traz (alvo de teste em Project.toml); um `julia --project=.
test/runtests.jl` direto NÃO, e aí o bloco é pulado — a suíte nunca fica vermelha por
ferramenta ausente. Aqua e JET rodam como **aviso** (relatório no log, sem reprovar),
como o sprint pede: são ruidosos em código novo, e a decisão foi introduzi-los sem travar
o CI já.

Os `import` ficam em ESCOPO DE ARQUIVO, numa instrução de topo ANTERIOR aos testsets. Se
ficassem dentro do testset, o `import` avançaria o *world age* no meio da instrução e os
métodos recém-trazidos (o `*` de Unitful com unidade, p.ex.) seriam "método novo demais"
para a própria instrução que os usa.
"""

using Test
using FPSOSiz

# Import por dependência, cada um numa instrução de topo (o `@eval import` avança o
# world age e a próxima instrução — o testset — já o enxerga). Ausente ⇒ flag false ⇒
# bloco pulado.
const _TEM_UNITFUL    = try; @eval import Unitful;    true; catch; false; end
const _TEM_ALLOCCHECK = try; @eval import AllocCheck; true; catch; false; end
const _TEM_AQUA       = try; @eval import Aqua;       true; catch; false; end
const _TEM_JET        = try; @eval import JET;        true; catch; false; end

# ---------------------------------------------------------------------------
# E.5 — homogeneidade dimensional com Unitful (só no teste; nunca em src/)
# ---------------------------------------------------------------------------

@testset "homogeneidade dimensional (E.5, Unitful)" begin
    if !_TEM_UNITFUL
        @test_skip "Unitful indisponível — rode com Pkg.test()"
    else
        # Referências por `Unitful.<unidade>` (acesso de campo, resolvido em runtime) e
        # NÃO pelo macro `u"..."`, que precisa de `@u_str` já em escopo ao PARSEAR. Reavalia
        # as relações FÍSICAS homogêneas e exige a dimensão do resultado. As empíricas
        # (Beggs-Robinson, Vogel, LGE, o 2,73 da válvula) têm unidade oculta no coeficiente
        # e são conferidas pelos NÚMEROS em test/fisica.jl — a classe mais cara do projeto.
        U = Unitful
        kg = U.kg; m = U.m; s = U.s; Pa = U.Pa; mol = U.mol; K = U.K; J = U.J; W = U.W
        dim = U.dimension
        # Stokes (Eq. 13, ramo laminar): v = Δρ·g·d²/(18·µ) → m/s
        drho = 150.0kg / m^3; gg = 9.8m / s^2; dd = 300e-6 * m; mu = 8e-3 * Pa * s
        rho = 850.0kg / m^3
        @test dim(drho * gg * dd^2 / (18mu)) == dim(1.0m / s)
        # Newton (Eq. 13): v = 1,74·√(g·d·Δρ/ρ) → m/s
        @test dim(1.74 * sqrt(gg * dd * drho / rho)) == dim(1.0m / s)
        # Gás real (Eq. 5): ρ_g = P·M/(z·R·T) → kg/m³
        P = 1.15e6 * Pa; M = 0.01661kg / mol; R = 8.314 * J / (mol * K); T = 313.15 * K
        @test dim(P * M / (0.977 * R * T)) == dim(1.0kg / m^3)
        # LMTD: diferença de temperatura → K
        dt1 = 40.0 * K; dt2 = 5.0 * K
        @test dim((dt1 - dt2) / log(dt1 / dt2)) == dim(1.0 * K)
        # U das resistências (série): 1/(1/h_o + 1/h_i) → W/(m²·K)
        hi = 2000.0 * W / (m^2 * K); ho = 800.0 * W / (m^2 * K)
        @test dim(1 / (1 / hi + 1 / ho)) == dim(1.0 * W / (m^2 * K))
    end
end

# ---------------------------------------------------------------------------
# AllocCheck — o passo do laço quente não aloca, provado em COMPILAÇÃO (crit. 8)
# ---------------------------------------------------------------------------

@testset "AllocCheck — o passo não aloca (crit. 8)" begin
    if !_TEM_ALLOCCHECK
        @test_skip "AllocCheck indisponível — rode com Pkg.test()"
    else
        SD = FPSOSiz.SongDynamics
        vals = FPSOSiz.valores_default_dinamico()
        pr = FPSOSiz.construir_params_dinamico(vals; malha_fechada = false, paralelo = false)
        v_w0, v_l0, p0 = FPSOSiz.estado_inicial_dinamico(pr, vals)
        e = SD.construir_estado(pr; v_w0, v_l0, p0)
        for kk in 1:pr.malha.n_gota
            vol = (π / 6) * pr.d_gota[kk]^3
            e.sigin_k[kk] = vol > 0 ? pr.ent.phi_agua_oleo_in * pr.frac_gota[kk] / vol : 0.0
        end
        # A asserção DURA de zero alocação está em test/fisica.jl (@allocated == 0). Aqui,
        # a prova em COMPILAÇÃO da AllocCheck, em modo aviso nesta introdução.
        try
            violacoes = AllocCheck.check_allocs(SD.passo!, (typeof(e), typeof(pr)))
            @info "AllocCheck: alocações provadas no passo (aviso)" n = length(violacoes)
        catch err
            @info "AllocCheck não concluiu (aviso)" erro = sprint(showerror, err)
        end
        @test true
    end
end

# ---------------------------------------------------------------------------
# Aqua — ambiguidade de método, unbound type params, piracy (AVISO)
# ---------------------------------------------------------------------------

@testset "Aqua — ambiguidade e sanidade do pacote (aviso)" begin
    if !_TEM_AQUA
        @test_skip "Aqua indisponível — rode com Pkg.test()"
    else
        # `detect_ambiguities` NÃO asserta (ao contrário de `test_ambiguities`), então o
        # relatório sai no log sem reprovar a suíte nesta introdução.
        try
            ambs = Aqua.detect_ambiguities(FPSOSiz; recursive = true)
            @info "Aqua: ambiguidades detectadas (aviso)" n = length(ambs)
        catch err
            @info "Aqua não concluiu (aviso)" erro = sprint(showerror, err)
        end
        @test true
    end
end

# ---------------------------------------------------------------------------
# JET — instabilidade de tipo e erro estático (AVISO)
# ---------------------------------------------------------------------------

@testset "JET — análise estática (aviso)" begin
    if !_TEM_JET
        @test_skip "JET indisponível — rode com Pkg.test()"
    else
        try
            rep = JET.report_package(FPSOSiz; toplevel_logger = nothing)
            @info "JET: relatório (aviso)" n = length(JET.get_reports(rep))
        catch err
            @info "JET não concluiu (aviso)" erro = sprint(showerror, err)
        end
        @test true
    end
end
