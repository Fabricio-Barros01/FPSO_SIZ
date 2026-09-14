"""
`test/fisica.jl` — bateria de invariantes de física (Entrega E).

Duas partes:

* **Dirigida pelo registro**: itera `equipments()`/`methods_for()` e aplica a mesma
  bateria universal a **todo** método registrado, pelo mecanismo de `test/registry.jl`.
  Equipamento novo herda a verificação sem escrever teste.
* **Módulo dinâmico (E.4)**: as invariantes de Song, que não passam pelo registro porque
  o dinâmico não é um método de dimensionamento. Conservação de massa, `H(V(H)) = H`,
  `σ ≥ 0`, `0 ≤ φ ≤ 1`, `φ_direita ≤ φ_esquerda` em regime, CFL como estado, determinismo
  bit a bit entre 1 e N threads, e degenerações que devolvem estado sem lançar.

Tolerâncias (medidas no gêmeo em Python, ver docs/validacao): 1e-12 relativo em geral,
1e-9 no `H(V(H))`.
"""

using Test
using FPSOSiz

const SD = FPSOSiz.SongDynamics
const PR = FPSOSiz.Propriedades

# `passo!` importado DIRETO (não `SD.passo!`): medir alocação por `SD.passo!` mede o
# boxing do getproperty do módulo, não a função — o passo real aloca zero (crit. 8).
import FPSOSiz.SongDynamics: passo! as _passo_direto!

"Alocação de um passo, medida em escopo tipado com a função referenciada diretamente."
function _aloc_passo(e, pr)
    _passo_direto!(e, pr)                     # warmup (compila)
    return @allocated _passo_direto!(e, pr)
end

# ===========================================================================
# Parte 1 — invariantes universais, dirigidas pelo registro
# ===========================================================================

@testset "invariantes universais de todo método registrado" begin
    eqs = FPSOSiz.equipments()
    @test !isempty(eqs)
    for eq in eqs
        for m in FPSOSiz.methods_for(eq)
            @testset "$(FPSOSiz.method_id(eq))/$(FPSOSiz.method_id(m))" begin
                @test FPSOSiz.method_id(m) isa Symbol
                @test !isempty(FPSOSiz.label(m))
                @test FPSOSiz.method_id(FPSOSiz.applies_to(m)) === FPSOSiz.method_id(eq)

                specs = FPSOSiz.parameters(m)
                @test specs isa Vector{FPSOSiz.ParameterSpec}
                for s in specs
                    @test !isempty(s.label)
                    @test s.min <= s.max
                    @test s.min <= s.default <= s.max
                end
                vals = FPSOSiz.defaults(specs)
                @test isempty(FPSOSiz.validate(specs, vals))
            end
        end
    end
end

# ===========================================================================
# Parte 2 — módulo dinâmico (E.4)
# ===========================================================================

_vals() = FPSOSiz.valores_default_dinamico()

@testset "módulo dinâmico (Song 2023) — E.4" begin

    @testset "geometria: H(V(H)) = H com o tampo elíptico (resíduo < 1e-9 m)" begin
        D, L, hi = 2.2, 3.5, 0.55
        for H in range(0.05, 2.15; length = 25)
            V = SD.volume_nivel(H, D, L, hi)
            H2 = SD.nivel_volume(V, D, L, hi)
            @test abs(H2 - H) < 1e-9
        end
        Vs = [SD.volume_nivel(H, D, L, hi) for H in range(0.01, 2.19; length = 50)]
        @test all(diff(Vs) .> 0)
    end

    @testset "propriedades: correlações conferem com as tabelas do sprint" begin
        @test isapprox(PR.viscosidade_oleo_bg(850.0, 313.15), 7.98e-3; rtol = 0.02)
        @test isapprox(PR.viscosidade_agua_vogel(313.15), 0.651e-3; rtol = 0.02)
        @test isapprox(PR.viscosidade_gas_lge(0.01661, 313.15, 7.51), 0.0121e-3; rtol = 0.05)
        pr = FPSOSiz.construir_params_dinamico(_vals())
        z = PR.compressibilidade(pr.fluido, 1150e3)
        @test 0.90 < z < 1.0
    end

    @testset "velocidade terminal: os três ramos e a fronteira" begin
        k = FPSOSiz.construir_params_dinamico(_vals()).k
        drho, rho, mu = 150.0, 850.0, 8e-3
        v1, r1 = SD.velocidade_terminal(5e-6, drho, rho, mu, k)   # 5 µm  → Stokes
        v2, r2 = SD.velocidade_terminal(5e-3, drho, rho, mu, k)   # 5 mm  → intermediário
        v3, r3 = SD.velocidade_terminal(5e-2, drho, rho, mu, k)   # 50 mm → Newton
        @test r1 == 1
        @test r2 == 2
        @test r3 == 3
        @test v1 > 0 && v2 > 0 && v3 > 0
        @test v1 < v2 < v3                                         # maior gota, mais rápida
    end

    @testset "simulação §3.1 (malha aberta) devolve trajetória finita" begin
        vals = _vals(); vals[:horizonte] = 300.0
        r = FPSOSiz.simular_dinamico(vals; malha_fechada = false)
        @test r isa SD.Trajetoria
        if r isa SD.Trajetoria
            @test !isempty(r.t)
            @test all(isfinite, r.P)
            @test all(isfinite, r.H_agua)
            @test all(isfinite, r.H_oleo)
            @test all(x -> 0.0 <= x <= 1.0, r.phi_esq)
            @test all(x -> 0.0 <= x <= 1.0, r.phi_dir)
            # em regime a gota continua decantando depois do vertedouro: φ_dir ≤ φ_esq
            @test r.phi_dir[end] <= r.phi_esq[end] + 1e-9
            @test all(x -> x > 1.0, r.folga_cfl)     # CFL folgado no default
        end
    end

    @testset "§3.1 fecha antes de §3.2 ser tentado (ordem, A.10)" begin
        vals = _vals(); vals[:horizonte] = 300.0
        r1 = FPSOSiz.simular_dinamico(vals; malha_fechada = false)
        @test r1 isa SD.Trajetoria
        if r1 isa SD.Trajetoria
            r2 = FPSOSiz.simular_dinamico(vals; malha_fechada = true)
            @test r2 isa SD.Trajetoria || r2 isa SD.Inviabilidade
            if r2 isa SD.Trajetoria
                @test all(isfinite, r2.P)
                @test all(x -> 0.0 <= x <= 1.0, r2.ab_gas)
            end
        end
    end

    @testset "determinismo bit a bit entre 1 e N threads" begin
        vals = _vals(); vals[:horizonte] = 60.0
        rs = FPSOSiz.simular_dinamico(vals; malha_fechada = false, paralelo = false)
        rp = FPSOSiz.simular_dinamico(vals; malha_fechada = false, paralelo = true)
        @test rs isa SD.Trajetoria && rp isa SD.Trajetoria
        if rs isa SD.Trajetoria && rp isa SD.Trajetoria
            @test rs.phi_esq == rp.phi_esq       # igualdade EXATA (redução sequencial)
            @test rs.phi_dir == rp.phi_dir
            @test rs.P == rp.P
            @test rs.H_agua == rp.H_agua
        end
    end

    @testset "CFL violado devolve estado, nunca exceção" begin
        vals = _vals(); vals[:dt_passo] = 120.0; vals[:horizonte] = 240.0
        r = FPSOSiz.simular_dinamico(vals; malha_fechada = false)
        @test r isa SD.Inviabilidade
        if r isa SD.Inviabilidade
            @test isfinite(r.dt_max)
            @test r.dt_max < vals[:dt_passo]
        end
    end

    @testset "degenerações devolvem estado, sem lançar" begin
        v0 = _vals(); v0[:q_oleo_in] = 0.0; v0[:q_agua_in] = 0.0; v0[:q_gas_in] = 0.0
        v0[:horizonte] = 60.0
        @test (FPSOSiz.simular_dinamico(v0; malha_fechada = false); true)
        vp = _vals(); vp[:p_jusante] = 4000.0; vp[:horizonte] = 60.0
        @test (FPSOSiz.simular_dinamico(vp; malha_fechada = false); true)
        vf = _vals(); vf[:temperatura] = 200.0; vf[:horizonte] = 30.0
        pr = FPSOSiz.construir_params_dinamico(vf)
        @test !isempty(pr.fluido.carimbos)     # T fora da faixa das correlações
        @test (FPSOSiz.simular_dinamico(vf; malha_fechada = false); true)
    end

    @testset "conservação de massa por passo (Eq. 1, 2 são acumulação exata)" begin
        pr = FPSOSiz.construir_params_dinamico(_vals(); malha_fechada = false)
        v_w0, v_l0, p0 = FPSOSiz.estado_inicial_dinamico(pr, _vals())
        e = SD.construir_estado(pr; v_w0, v_l0, p0)
        for kk in 1:pr.malha.n_gota
            vol = (π / 6) * pr.d_gota[kk]^3
            e.sigin_k[kk] = vol > 0 ? pr.ent.phi_agua_oleo_in * pr.frac_gota[kk] / vol : 0.0
        end
        vw_antes, vl_antes = e.v_w, e.v_l
        Hw, Hl, P, z, rho_g = SD.niveis_e_pressao(pr, e.v_w, e.v_l, e.n)
        Qo, Qw, Qg = SD.vazoes_saida(pr, P, rho_g,
                                     clamp(e.ab_oleo, 0.0, 1.0),
                                     clamp(e.ab_agua, 0.0, 1.0),
                                     clamp(e.ab_gas, 0.0, 1.0))
        esperado_dvw = (pr.ent.q_agua_in - Qw) * pr.dt                          # Eq. 2
        esperado_dvl = (pr.ent.q_agua_in + pr.ent.q_oleo_in - Qw - Qo) * pr.dt  # Eq. 1
        SD.passo!(e, pr)
        @test abs((e.v_w - vw_antes) - esperado_dvw) < 1e-12 * max(abs(esperado_dvw), 1.0)
        @test abs((e.v_l - vl_antes) - esperado_dvl) < 1e-12 * max(abs(esperado_dvl), 1.0)
    end

    @testset "o passo do laço quente é tipo-estável e não aloca (crit. 8)" begin
        pr = FPSOSiz.construir_params_dinamico(_vals(); malha_fechada = false,
                                               paralelo = false)
        v_w0, v_l0, p0 = FPSOSiz.estado_inicial_dinamico(pr, _vals())
        e = SD.construir_estado(pr; v_w0, v_l0, p0)
        for kk in 1:pr.malha.n_gota
            vol = (π / 6) * pr.d_gota[kk]^3
            e.sigin_k[kk] = vol > 0 ? pr.ent.phi_agua_oleo_in * pr.frac_gota[kk] / vol : 0.0
        end
        SD.passo!(e, pr)                                    # warmup
        @test (@inferred SD.passo!(e, pr)) isa Tuple{Bool,Float64}
        @test _aloc_passo(e, pr) == 0
    end
end

# ===========================================================================
# Parte 3 — vasos (E.1), dirigida pelo registro
# ===========================================================================

"Constrói as restrições de um método de vaso a partir dos defaults; `nothing` se não montar."
function _cons_vaso(met)
    vals = merge(FPSOSiz.defaults(FPSOSiz.stream_parameters(met)),
                 FPSOSiz.defaults(FPSOSiz.parameters(met)))
    entrada = try
        FPSOSiz.case_input(met, vals)
    catch
        return nothing
    end
    k = FPSOSiz.constants(FPSOSiz.method_config(met))
    ok, cons, _ = FPSOSiz.sizing_constraints(met, entrada,
                        FPSOSiz.with_defaults(FPSOSiz.parameters(met), vals), k)
    return ok ? cons : nothing
end

@testset "vasos — invariantes de decantação (E.1)" begin
    for eq in FPSOSiz.equipments(), met in FPSOSiz.methods_for(eq)
        met isa FPSOSiz.AbstractVesselMethod || continue
        @testset "$(FPSOSiz.method_id(met))" begin
            cons = _cons_vaso(met)
            cons === nothing && continue

            # Leff estritamente decrescente no diâmetro (o comprimento exigido cai quando
            # o vaso engorda). Cobre gás (∝ d⁻¹) e líquido (∝ d⁻²) juntos.
            ds = collect(range(2000.0, 8000.0; length = 40))
            leffs = [FPSOSiz.requirement(met, d, cons) for d in ds]
            @test all(l -> isfinite(l) && l > 0, leffs)
            @test all(diff(leffs) .< 0)

            # cross_section: repartição de verdade sobre a grade inteira (é d-independente,
            # mas conferimos que o que ela devolve é geometria possível em todo ponto).
            faixas = FPSOSiz.cross_section(met, cons)
            @test all(l -> l.fracao > 0 && isfinite(l.fracao), faixas)
            @test isapprox(sum(l.fracao for l in faixas), 1.0; atol = 1e-9)
        end
    end
end

# ===========================================================================
# Parte 4 — trocador (E.2): funções puras, sem registro
# ===========================================================================

@testset "trocador — ΔT_lm, F e o laço ε-NTU (E.2)" begin
    @testset "ΔT_lm: simetria, limites e o limite removível" begin
        # Pares bem separados: a desigualdade GM ≤ LM ≤ AM é apertada demais em 1e-9
        # perto de ΔT₁ = ΔT₂, onde a fórmula é mal-condicionada — o limite removível é
        # testado à parte logo abaixo.
        for (a, b) in ((5.0, 40.0), (10.0, 50.0), (3.0, 90.0), (18.0, 22.0))
            lm = FPSOSiz.lmtd(a, b)
            @test lm ≈ FPSOSiz.lmtd(b, a)                    # simétrica
            @test sqrt(a * b) - 1e-9 <= lm <= (a + b) / 2 + 1e-9
        end
        @test FPSOSiz.lmtd(30.0, 30.0) ≈ 30.0                # ΔT₁ = ΔT₂ (limite removível)
        @test FPSOSiz.lmtd(25.0, 25.0) ≈ 25.0
    end

    @testset "F ≤ 1 sempre, e F → 1 quando P → 0" begin
        for p in (0.05, 0.2, 0.4, 0.6), r in (0.3, 1.0, 2.0, 4.0)
            f = FPSOSiz.f_correction_1_2(p, r)
            isfinite(f) || continue
            @test f <= 1 + 1e-9
        end
        @test FPSOSiz.f_correction_1_2(1e-6, 1.0) > 0.999
    end

    @testset "U abaixo do h de cada lado" begin
        for h_i in (500.0, 2000.0), h_o in (800.0, 3000.0)
            u = FPSOSiz.overall_u(h_i, h_o, 1e-4, 2e-4, 0.016, 0.020, 50.0)
            @test 0 < u < min(h_i, h_o)
        end
    end

    @testset "LMTD contra ε-NTU em contracorrente puro (o caso-ouro que falta)" begin
        # Para 1000 deveres sorteados, o U·A do LMTD prediz o mesmo q que o ε-NTU.
        rng = 0
        piores = 0.0
        for _ in 1:1000
            rng = (1103515245 * rng + 12345) % (1 << 31)     # LCG determinístico
            frac(n) = ((1103515245 * (rng + n) + 12345) % (1 << 31)) / (1 << 31)
            Th_in = 120 + 60 * frac(1)
            Tc_in = 20 + 30 * frac(2)
            Th_in - Tc_in > 20 || continue
            Ch = 1.0 + 4 * frac(3)
            Cc = 1.0 + 4 * frac(4)
            q = 0.3 * min(Ch, Cc) * (Th_in - Tc_in) * (0.3 + 0.5 * frac(5))
            Th_out = Th_in - q / Ch
            Tc_out = Tc_in + q / Cc
            Th_out > Tc_in && Th_in > Tc_out || continue
            dt1 = Th_in - Tc_out
            dt2 = Th_out - Tc_in
            (dt1 > 0 && dt2 > 0) || continue
            ua = q / FPSOSiz.lmtd(dt1, dt2)                  # F = 1 em contracorrente
            cmin, cmax = minmax(Ch, Cc)
            ntu = ua / cmin
            eps = FPSOSiz.effectiveness_ntu_counterflow(ntu, cmin / cmax)
            q_ntu = eps * cmin * (Th_in - Tc_in)
            piores = max(piores, abs(q_ntu - q) / q)
        end
        @test piores < 1e-9
    end
end

# ===========================================================================
# Parte 5 — pinch (E.3): via PinchAnalysis
# ===========================================================================

const _KP = FPSOSiz.PinchAnalysis

# ΔH de uma corrente de um segmento: mcp·|Δt|. Positivo sempre; o sinal é o papel.
_dh(s) = abs(s.segments[1].t_out - s.segments[1].t_in) * s.segments[1].mcp
_frio(s) = s.segments[1].t_out > s.segments[1].t_in

@testset "pinch — balanço, cascata e monotonicidade (E.3)" begin
    correntes = [_KP.ThermalStream("1 fria", 20, 135, 2.0),
                 _KP.ThermalStream("2 quente", 170, 60, 3.0),
                 _KP.ThermalStream("3 fria", 80, 140, 4.0),
                 _KP.ThermalStream("4 quente", 150, 30, 1.5)]

    @testset "balanço global: QHmin − QCmin = ΣΔH_frias − ΣΔH_quentes" begin
        r = _KP.problem_table(correntes, 10.0)
        @test r.feasible
        soma = sum(_frio(s) ? _dh(s) : -_dh(s) for s in correntes)
        @test isapprox(r.q_h_min - r.q_c_min, soma; atol = 1e-9 * max(abs(soma), 1))
    end

    @testset "a cascata factível nunca é negativa" begin
        r = _KP.problem_table(correntes, 10.0)
        @test all(x -> x >= -1e-9, r.cascade_feasible)
        @test minimum(r.cascade_feasible) < 1e-6              # toca zero no pinch
    end

    @testset "QHmin e QCmin não decrescem com ΔTmin" begin
        qhs = Float64[]; qcs = Float64[]
        for dt in (2.0, 6.0, 10.0, 14.0, 20.0)
            r = _KP.problem_table(correntes, dt)
            push!(qhs, r.q_h_min); push!(qcs, r.q_c_min)
        end
        @test all(diff(qhs) .>= -1e-9)
        @test all(diff(qcs) .>= -1e-9)
    end

    @testset "os alvos independem da ordem das correntes" begin
        r  = _KP.problem_table(correntes, 10.0)
        rr = _KP.problem_table(reverse(correntes), 10.0)
        @test isapprox(r.q_h_min, rr.q_h_min; atol = 1e-9)
        @test isapprox(r.q_c_min, rr.q_c_min; atol = 1e-9)
    end
end
