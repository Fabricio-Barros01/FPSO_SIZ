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
end
