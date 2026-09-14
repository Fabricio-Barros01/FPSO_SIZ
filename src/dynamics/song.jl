"""
Módulo dinâmico do separador trifásico horizontal — Song et al. (2023).

Fonte: Song, S.; Liu, X.; Li, C.; Li, Z.; Zhang, S.; Wu, W.; Shi, B.; Kang, Q.; Wu, H.;
Gong, J. *Dynamic Simulator for Three-Phase Gravity Separators in Oil Production
Facilities.* **ACS Omega 2023, 8, 6078−6089**, doi 10.1021/acsomega.2c08267. Modelo em
§2 (Eq. 1–16); verificação em §3.

Simulador dinâmico para **sintonia das três malhas** (pressão, nível de óleo, nível de
água) e **monitoramento no tempo**. Não devolve diâmetro nem comprimento, não alimenta
otimização, e **não compartilha equacionamento nem premissa** com Stewart & Arnold,
Alves & Komesu, Saari, Moran ou Kemp.

# Isolamento — a regra que manda sobre as outras

Este é um **subapp independente**, e segue o artigo e só o artigo. Como `analysis/
pinch.jl` e `dynamics/propriedades.jl`, entra em `FPSOSiz.jl` **antes de `interfaces.jl`**
— nenhum `ParameterSpec`, `AbstractSizingMethod` nem `field_units` existe quando ele
compila. Ele **não importa nada de `src/sizing/`**. As constantes chegam por argumento
(a `Constantes` montada do TOML pelo adaptador), como `sizing_constraints(m, s, p, k)`
recebe `k` — não há literal numérico neste arquivo. `converge_drag` não é chamado, não é
consultado e não serve de referência: a velocidade terminal vem das Eq. 13–15.
`g = 9,8 m/s²` (nomenclatura do artigo), no TOML.

# As quatro premissas do artigo, herdadas sem alteração (§2, p. 6079)

1. Gotículas em equilíbrio dinâmico de agregação e quebra na entrada; **coalescência e
   fragmentação ignoradas** dentro do vaso.
2. Saídas de óleo e de água sem gás.
3. Gás dissolvido ignorado.
4. **Somente conservação de massa**; energia ignorada.

# As três leituras interpretativas do artigo

* O `1` impresso solto após o radical do termo de gás na Eq. 6 (p. 6080) é **símbolo
  espúrio** e foi ignorado. O coeficiente `2,73` deriva da definição de Cv:
  `W = 31,6·Kv·√(ΔP·ρ) = 27,34·Cv·√(ΔP[bar]·ρ)`, que em kPa dá **2,734**. Conferência:
  com `C_v` = 57,3018 e ΔP = 950 kPa a válvula de água dá 152,5 m³/h a 100 % → 31,12 m³/h
  exige 0,204 de abertura, contra 0,19 publicado.
* A **fração de água no óleo** não tem equação numerada. Leitura coerente com a Eq. 9:
  `φ = Σ_k σ_k·(π/6)·d_k³`. **Inferida a partir da Eq. 9.**
* A **vazão de gás** publicada (3,696 kmol/h e 0,1936 m³/h) é inconsistente; o default
  reconstruído é **8,175 m³/h** (ρ_g de Peng-Robinson a 1150 kPa/40 °C ≈ 7,51 kg/m³).

# Leituras geométricas — o que a Figura 1 implica e o texto não numera

O artigo mede o nível de água à esquerda do vertedouro e o nível de óleo à direita, mas
as Eq. 1–3 dão volumes **à esquerda** (comprimento `L_esq`). Onde o bookkeeping da
geometria não é explícito, adotamos e **registramos** aqui:

* `H_o` (nível de óleo) := o nível de líquido total à esquerda do vertedouro, `H_l`,
  invertido da Eq. 3 sobre `V_l`. A malha de óleo é a faixa `[H_w, H_l]`.
* `V_g` (Eq. 5) := volume interno do vaso (comprimento `L_total`, dois tampos) menos o
  volume de líquido com o nível `H_l` estendido ao vaso inteiro. É a leitura que fecha o
  balanço de gás sem um estado de transbordo separado; o caso-ouro de §3.1 é o juiz.

Estas escolhas estão isoladas em [`niveis_e_pressao`](@ref) e são o primeiro lugar a
ajustar se §3.1 não reproduzir.
"""
module SongDynamics

using ..Propriedades

export Constantes, Geometria, Malha, Entradas, Ganhos, Setpoints, Params, Estado
export construir_estado, passo!, simular, Trajetoria, Inviabilidade
export volume_nivel, nivel_volume, area_segmento, largura_corda, volume_vaso
export vazao_valvula, velocidade_terminal, alpha_valvula, y_expansao
export pi_incremental, niveis_e_pressao, fracao_agua_oleo
export rhs!, empacotar, verificar_cfl, regime_permanente
export metricas_malha, varredura_ganhos, MetricaMalha

# ===========================================================================
# Constantes e parâmetros — tudo do TOML, montado pelo adaptador
# ===========================================================================

"Constantes do TOML (Eq. 5–15). Nenhuma nasce no `.jl`; todas com proveniência no TOML."
struct Constantes
    r_gas::Float64            # J/(mol·K), Eq. 5
    gravidade::Float64        # m/s², nomenclatura do artigo (9,8)
    isa_coeficiente::Float64  # Eq. 6, derivado de Kv/Cv (2,73)
    fp::Float64               # Eq. 6
    xt::Float64               # Eq. 8
    fk::Float64               # Eq. 8
    stokes_divisor::Float64   # Eq. 13, ramo laminar (18)
    intermediario_c::Float64  # Eq. 13, ramo intermediário (0,153)
    newton_c::Float64         # Eq. 13, ramo de Newton (1,74)
    d1_c::Float64             # Eq. 14 (3,3)
    d2_c::Float64             # Eq. 15 (43,5)
    alfa_limiar_gas::Float64  # Eq. 7 (0,1)
    alfa_fator::Float64       # Eq. 7 (10,0)
    cv_oleo::Float64          # §3.1
    cv_agua::Float64          # §3.1
    cv_gas::Float64           # §3.1
end

"Geometria do vaso (§3), em m."
struct Geometria
    d_vaso::Float64
    l_esquerda::Float64       # comprimento à esquerda do vertedouro (L da Eq. 3)
    l_total::Float64
    h_vertedouro::Float64
    h_tampo::Float64          # h_i da Eq. 3
end

"Discretização da fase dispersa (§2.2)."
struct Malha
    n_colunas::Int            # N_x: N_x−1 à esquerda, 1 à direita
    n_oleo::Int               # N_o: corpos na camada de óleo
    n_agua::Int               # N_w: corpos na camada de água
    n_gota::Int               # N_k: faixas de tamanho de gotícula
end

"Entradas de operação, já em SI (T em K, vazões em m³/s, pressão em Pa)."
struct Entradas
    temperatura::Float64      # K
    q_oleo_in::Float64        # m³/s
    q_agua_in::Float64        # m³/s
    q_gas_in::Float64         # m³/s
    p_jusante::Float64        # Pa (as três válvulas)
    phi_agua_oleo_in::Float64 # fração volumétrica de água nas gotículas do óleo de entrada
end

"Ganhos das três malhas PI (Eq. 16). `KP` em kPa⁻¹/m⁻¹/m⁻¹; `KI` em s."
struct Ganhos
    kp_p::Float64;  ki_p::Float64      # pressão
    kp_ol::Float64; ki_ol::Float64     # nível de óleo
    kp_wl::Float64; ki_wl::Float64     # nível de água
end

"Setpoints das três variáveis, em SI (P em Pa, níveis em m)."
struct Setpoints
    p::Float64
    h_oleo::Float64
    h_agua::Float64
end

"""
Parâmetros completos de uma simulação. `d_gota` (m) e `frac_gota` (fração numérica por
faixa, Σ = 1) descrevem a distribuição da Figura 4. `malha_fechada` liga os três PI;
`false` congela as aberturas em `ab_*`. `guardar_saturado` é a chave de teste de
anti-windup (A.5): `true` guarda a saída saturada (decisão adotada), `false` a não
saturada. `paralelo` liga `Threads.@threads` no transporte (aceleração, não condição).
"""
struct Params
    k::Constantes
    geo::Geometria
    malha::Malha
    ent::Entradas
    ganhos::Ganhos
    sp::Setpoints
    fluido::Fluido
    d_gota::Vector{Float64}     # m, comprimento N_k
    frac_gota::Vector{Float64}  # fração numérica por faixa, Σ = 1
    dt::Float64                 # s
    horizonte::Float64          # s
    cadencia::Float64           # s
    malha_fechada::Bool
    ab_oleo::Float64            # abertura fixa (malha aberta)
    ab_agua::Float64
    ab_gas::Float64
    guardar_saturado::Bool
    janela::Float64             # janela de regime permanente, s
    paralelo::Bool              # Threads.@threads sobre k no transporte (aceleração)
end

# ===========================================================================
# Geometria — Eq. 3 e sua inversão (isoladas; a decantação depende delas)
# ===========================================================================

"Área do segmento circular inferior de altura `H` num círculo de diâmetro `D`, em m²."
function area_segmento(H::Float64, D::Float64)
    H <= 0 && return 0.0
    H >= D && return π * D^2 / 4
    R = D / 2
    c = (H - R) / R                       # ∈ (−1, 1)
    return R^2 * (acos(clamp(-c, -1.0, 1.0)) - (-c) * sqrt(max(1 - c^2, 0.0)))
end

"Largura da corda (m) na altura `H` (medida do fundo) de um círculo de diâmetro `D`."
function largura_corda(H::Float64, D::Float64)
    (H <= 0 || H >= D) && return 0.0
    R = D / 2
    return 2 * sqrt(max(R^2 - (H - R)^2, 0.0))
end

"""
    volume_nivel(H, D, L, h_i) -> V

Eq. 3: volume de líquido de nível `H` num cilindro horizontal de diâmetro `D`,
comprimento `L` e tampo elíptico de largura de superfície `h_i`, tudo em m. A primeira
parcela é o cilindro; a segunda, os tampos.
"""
function volume_nivel(H::Float64, D::Float64, L::Float64, h_i::Float64)
    Hc = clamp(H, 0.0, D)
    cil = L * (D^2 / 4 * acos(clamp(1 - 2Hc / D, -1.0, 1.0)) -
               sqrt(max(D * Hc - Hc^2, 0.0)) * (D / 2 - Hc))
    tampo = (π * h_i / D) * (D^2 / 4 * (Hc - D / 2) - (Hc - D / 2)^3 / 3 + D^3 / 12)
    return cil + tampo
end

"Volume interno total do vaso (nível = `D`)."
volume_vaso(g::Geometria) = volume_nivel(g.d_vaso, g.d_vaso, g.l_total, g.h_tampo)

"""
    nivel_volume(V, D, L, h_i) -> H

Inversão numérica da Eq. 3 por bisseção — `V(H)` é monótona em `0 < H < D`. Implementada
aqui (A.4), sem dependência. `H(V(H)) = H` com resíduo `< 1e-9 m` é invariante de teste.
"""
function nivel_volume(V::Float64, D::Float64, L::Float64, h_i::Float64)
    V <= 0 && return 0.0
    Vmax = volume_nivel(D, D, L, h_i)
    V >= Vmax && return D
    lo, hi = 0.0, D
    for _ in 1:100                        # 100 passos ⇒ resíduo em H bem abaixo de 1e-9
        mid = 0.5 * (lo + hi)
        volume_nivel(mid, D, L, h_i) < V ? (lo = mid) : (hi = mid)
    end
    return 0.5 * (lo + hi)
end

# ===========================================================================
# Válvulas — Eq. 6 a 8
# ===========================================================================

"Eq. 7: fração de vapor ajustada. `hg` = fração mássica de gás na entrada da válvula."
function alpha_valvula(hg::Float64, k::Constantes)
    hg >= k.alfa_limiar_gas && return 1.0
    hg <= 0.0 && return 0.0
    return k.alfa_fator * hg
end

"Eq. 8: coeficiente de expansão do gás, saturado no choke em 2/3."
function y_expansao(dP::Float64, p_in::Float64, k::Constantes)
    p_in <= 0 && return 1.0
    y = 1 - (dP / p_in) / (3 * k.fk * k.xt)
    return clamp(y, 2 / 3, 1.0)
end

"""
    vazao_valvula(abertura, cv, alpha, p_in, p_out, ρ_l, ρ_g, k) -> Q [m³/s]

Eq. 6: vazão volumétrica pela válvula. `p_in`/`p_out` em **Pa** (convertidos a kPa aqui,
onde o `2,73` fecha), `ρ` em kg/m³. `G` sai em kg/h e vira m³/s pela densidade da fase
que passa (líquido se `alpha=0`, gás se `alpha=1`). `ΔP ≤ 0` devolve 0 — sem fluxo
reverso — e é uma degeneração que o chamador carimba.
"""
function vazao_valvula(abertura::Float64, cv::Float64, alpha::Float64,
                       p_in::Float64, p_out::Float64, rho_l::Float64, rho_g::Float64,
                       k::Constantes)
    dP_kpa = (p_in - p_out) / 1000.0
    dP_kpa <= 0 && return 0.0
    cve = abertura * cv
    liq = k.isa_coeficiente * (1 - alpha) * k.fp * cve * sqrt(rho_l * dP_kpa)    # kg/h
    y = y_expansao(p_in - p_out, p_in, k)
    gas = k.isa_coeficiente * alpha * k.fp * cve * y * sqrt(rho_g * dP_kpa)      # kg/h
    G = liq + gas                                                              # kg/h
    rho = alpha >= 1.0 ? rho_g : rho_l
    rho <= 0 && return 0.0
    return (G / rho) / 3600.0                                                  # m³/h → m³/s
end

# ===========================================================================
# Velocidade terminal — Eq. 13 a 15 (carimba o ramo)
# ===========================================================================

"""
    velocidade_terminal(d, Δρ, ρ, µ, k) -> (v_y, ramo)

Eq. 13–15: velocidade vertical (m/s, magnitude) de uma gotícula de diâmetro `d` (m) numa
fase contínua de densidade `ρ` e viscosidade `µ` (Pa·s), com diferença de densidade `Δρ`.
`ramo` ∈ {1 = Stokes, 2 = intermediário, 3 = Newton} é carimbado (A.4). `d₁`, `d₂` pela
Eq. 14–15.
"""
function velocidade_terminal(d::Float64, drho::Float64, rho::Float64, mu::Float64,
                             k::Constantes)
    base = (mu^2 / (rho * k.gravidade * drho))^(1 / 3)
    d1 = k.d1_c * base
    d2 = k.d2_c * base
    if d < d1
        return (drho * k.gravidade * d^2 / (k.stokes_divisor * mu), 1)
    elseif d <= d2
        return (k.intermediario_c * k.gravidade^0.714 * d^1.143 * drho^0.714 /
                (mu^0.428 * rho^0.286), 2)
    else
        return (k.newton_c * sqrt(k.gravidade * d * drho / rho), 3)
    end
end

# ===========================================================================
# Controlador PI incremental — Eq. 16, com saturação e anti-windup
# ===========================================================================

"""
    pi_incremental(f_prev, e, e_prev, KP, KI, dt; guardar_saturado) -> (saida, memoria)

Eq. 16 na forma incremental: `f(t) = f(t−1) + KP·[e(t) − e(t−1) + (1/KI)·e(t)·Δt]`.
`saida` é a abertura efetiva (saturada em [0,1]); `memoria` é o `f(t−1)` do próximo passo
— **saturada** quando `guardar_saturado` (decisão adotada, A.5), não saturada com a chave
de teste desligada. Guardar a saturada é integração condicional: o controlador sai do
batente no instante em que o erro inverte, sem o windup.
"""
function pi_incremental(f_prev::Float64, e::Float64, e_prev::Float64,
                        KP::Float64, KI::Float64, dt::Float64; guardar_saturado::Bool)
    f = f_prev + KP * (e - e_prev + e * dt / KI)
    fsat = clamp(f, 0.0, 1.0)
    return (fsat, guardar_saturado ? fsat : f)
end

# ===========================================================================
# Estado — struct de campos concretos, com buffers pré-alocados (zero-alloc)
# ===========================================================================

"""
Estado mutável da simulação. `sig`/`sig_buf` são os dois buffers de σ da fase dispersa
**água-em-óleo** (Eq. 9), indexados `[j, i, k]` com `j` (vertical, na faixa de óleo)
contíguo — a direção do stencil mais frequente. Trocados a cada passo (A.9). Os demais
vetores são work buffers pré-alocados para o passo não alocar.

`sig` tem dimensões `[N_o, N_x, N_k]`: `N_o` camadas de óleo, `N_x` colunas, `N_k`
faixas de tamanho. As gotículas de água **afundam** para a interface (Eq. 11 literal,
`v_y > 0` = para baixo).
"""
mutable struct Estado
    v_w::Float64              # volume de água à esquerda do vertedouro, m³
    v_l::Float64              # volume de líquido total à esquerda, m³
    n::Float64               # mols de gás
    ab_oleo::Float64
    ab_agua::Float64
    ab_gas::Float64
    e_p_prev::Float64
    e_ol_prev::Float64
    e_wl_prev::Float64
    t::Float64
    passo::Int
    sig::Array{Float64,3}
    sig_buf::Array{Float64,3}
    # work buffers (comprimento N_k / N_o+1)
    vy_k::Vector{Float64}
    ramo_k::Vector{Int}
    sigin_k::Vector{Float64}
    yface::Vector{Float64}   # alturas das fronteiras das camadas de óleo, N_o+1
    aface::Vector{Float64}   # área de segmento de cada camada de óleo, N_o
    wbound::Vector{Float64}  # largura de corda em cada fronteira, N_o+1
end

"""
    construir_estado(p; v_w0, v_l0, p0) -> Estado

Constrói o estado inicial. `v_w0`, `v_l0` (m³) e `p0` (Pa) vêm dos níveis e pressão
iniciais do artigo, já convertidos em volume/mols pelo adaptador.
"""
function construir_estado(p::Params; v_w0::Float64, v_l0::Float64, p0::Float64)
    No, Nx, Nk = p.malha.n_oleo, p.malha.n_colunas, p.malha.n_gota
    z0 = compressibilidade(p.fluido, p0)
    V_g0 = _vg(p, v_l0)
    n0 = p0 * V_g0 / (z0 * p.k.r_gas * p.ent.temperatura)
    sig  = zeros(Float64, No, Nx, Nk)
    sigb = zeros(Float64, No, Nx, Nk)
    return Estado(v_w0, v_l0, n0,
                  p.ab_oleo, p.ab_agua, p.ab_gas,
                  0.0, 0.0, 0.0, 0.0, 0,
                  sig, sigb,
                  zeros(Float64, Nk), zeros(Int, Nk), zeros(Float64, Nk),
                  zeros(Float64, No + 1), zeros(Float64, No), zeros(Float64, No + 1))
end

# ===========================================================================
# Níveis, pressão e vazões — Eq. 1, 2, 4, 5 (as leituras geométricas moram aqui)
# ===========================================================================

"Volume de gás (Eq. 5): vaso inteiro menos o líquido com o nível `H_l` estendido a `L_total`."
function _vg(p::Params, v_l::Float64)
    g = p.geo
    Hl = nivel_volume(v_l, g.d_vaso, g.l_esquerda, g.h_tampo)
    return volume_vaso(g) - volume_nivel(Hl, g.d_vaso, g.l_total, g.h_tampo)
end

"""
    niveis_e_pressao(p, v_w, v_l, n) -> (H_w, H_l, P, z, ρ_g)

Deriva do estado os níveis (Eq. 3 invertida), a pressão (Eq. 5) e a densidade do gás.
`H_l` é o nível de líquido à esquerda, adotado como o nível de óleo `H_o` (ver o
cabeçalho). Nunca lança: níveis fora de `[0, D]` saem saturados e o chamador decide.
"""
function niveis_e_pressao(p::Params, v_w::Float64, v_l::Float64, n::Float64)
    g = p.geo
    Hw = nivel_volume(v_w, g.d_vaso, g.l_esquerda, g.h_tampo)
    Hl = nivel_volume(v_l, g.d_vaso, g.l_esquerda, g.h_tampo)
    Vg = _vg(p, v_l)
    Vg = max(Vg, 1e-9)                    # o balanço de gás não divide por zero
    # z depende de P e P de z (Eq. 5): uma iteração de ponto fixo curta basta, z varia < 3 %
    P = p.ent.p_jusante
    z = compressibilidade(p.fluido, P)
    for _ in 1:8
        P = z * p.k.r_gas * p.ent.temperatura * n / Vg
        z = compressibilidade(p.fluido, P)
    end
    rho_g = densidade_gas(P, p.fluido.M, z, p.ent.temperatura, p.k.r_gas)
    return (Hw, Hl, P, z, rho_g)
end

"""
    vazoes_saida(p, P, rho_g, ab_o, ab_w, ab_g) -> (Qo, Qw, Qg)

Vazões volumétricas de saída (m³/s) das três válvulas, Eq. 6–8. Óleo e água são líquido
puro (α = 0); gás é α = 1.
"""
function vazoes_saida(p::Params, P::Float64, rho_g::Float64,
                      ab_o::Float64, ab_w::Float64, ab_g::Float64)
    k, f = p.k, p.fluido
    Qo = vazao_valvula(ab_o, k.cv_oleo, 0.0, P, p.ent.p_jusante, f.rho_oleo, rho_g, k)
    Qw = vazao_valvula(ab_w, k.cv_agua, 0.0, P, p.ent.p_jusante, f.rho_agua, rho_g, k)
    Qg = vazao_valvula(ab_g, k.cv_gas, 1.0, P, p.ent.p_jusante, f.rho_agua, rho_g, k)
    return (Qo, Qw, Qg)
end

# ===========================================================================
# Fase dispersa — Eq. 9 a 12, upwind de 1ª ordem com Euler explícito
# ===========================================================================

"""
    _remalhar!(e, p, Hw, Hl)

Recalcula as fronteiras `[H_w, H_l]` das `N_o` camadas de óleo (iguais em altura), suas
áreas de segmento e as larguras de corda nas fronteiras — nos work buffers, sem alocar.
Posiciona as camadas de modo que a interface `H_w` seja a fronteira inferior (§2.2: a
interface não cai dentro de um volume).
"""
function _remalhar!(e::Estado, p::Params, Hw::Float64, Hl::Float64)
    No = p.malha.n_oleo
    D = p.geo.d_vaso
    dy = (Hl - Hw) / No
    A_ant = area_segmento(Hw, D)
    for j in 1:No+1
        y = Hw + (j - 1) * dy
        e.yface[j] = y
        e.wbound[j] = largura_corda(y, D)
    end
    for j in 1:No
        A_top = area_segmento(e.yface[j + 1], D)
        e.aface[j] = A_top - A_ant
        A_ant = A_top
    end
    return nothing
end

"""
    _velocidades_gota!(e, p) -> nothing

Preenche `vy_k`/`ramo_k` com a velocidade terminal (Eq. 13–15) de cada faixa de gotícula
de **água em óleo** (afunda): `Δρ = ρ_w − ρ_o`, `µ = µ_o`, `ρ = ρ_o`.
"""
function _velocidades_gota!(e::Estado, p::Params)
    f = p.fluido
    drho = f.rho_agua - f.rho_oleo
    for kk in 1:p.malha.n_gota
        v, r = velocidade_terminal(p.d_gota[kk], drho, f.rho_oleo, f.mu_oleo, p.k)
        e.vy_k[kk] = v
        e.ramo_k[kk] = r
    end
    return nothing
end

"Comprimento (m) da coluna `i`: `N_x−1` iguais à esquerda, 1 à direita do vertedouro."
function _dx(p::Params, i::Int)
    g = p.geo
    return i < p.malha.n_colunas ? g.l_esquerda / (p.malha.n_colunas - 1) :
                                   (g.l_total - g.l_esquerda)
end

"""
    _transporte_k!(e, p, vx_o, kk) -> nothing

Uma faixa `k` do transporte da fase dispersa água-em-óleo (Eq. 10–12), upwind de 1ª
ordem, Euler explícito. Escreve `sig_buf[:, :, kk]` a partir de `sig`. Convectivo em `x`
(óleo esquerda→direita, feed na coluna 1), empuxo em `y` (gotícula afunda, Eq. 11
literal). **Zero-alloc e tipo-estável** — é a peça que `@allocated`/`@inferred` cobram
(A.9); `@inbounds`/`@simd` na dimensão contígua `j`.
"""
@inline function _transporte_k!(e::Estado, p::Params, vx_o::Float64, kk::Int)
    No, Nx = p.malha.n_oleo, p.malha.n_colunas
    dt = p.dt
    vy = e.vy_k[kk]
    sin_k = e.sigin_k[kk]
    @inbounds for i in 1:Nx
        dx = _dx(p, i)
        @simd for j in 1:No
            sig_ij = e.sig[j, i, kk]
            sig_esq = i == 1 ? sin_k : e.sig[j, i - 1, kk]
            dsig_x = vx_o * (sig_esq - sig_ij) * dt / dx
            sig_cima = j == No ? 0.0 : e.sig[j + 1, i, kk]
            fluxo = e.wbound[j + 1] * sig_cima - e.wbound[j] * sig_ij
            dsig_y = e.aface[j] > 0 ? vy * fluxo * dt / e.aface[j] : 0.0
            novo = sig_ij + dsig_x + dsig_y
            e.sig_buf[j, i, kk] = novo < 0 ? 0.0 : novo   # σ ≥ 0 (E.4)
        end
    end
    return nothing
end

"""
    _transporte!(e, p, vx_o) -> nothing

Percorre as `N_k` faixas. Serial por default (zero-alloc, o baseline correto e
determinístico — "paralelismo é aceleração, nunca condição de funcionamento", A.9);
`p.paralelo` liga `Threads.@threads` sobre `k`, que é livre de condição de corrida porque
as Eq. 10–11 não acoplam `k` com `k'`. As reduções (φ) continuam sequenciais, então o
resultado é idêntico **bit a bit** com 1 ou N threads (A.9, E.4).
"""
function _transporte!(e::Estado, p::Params, vx_o::Float64)
    Nk = p.malha.n_gota
    if p.paralelo
        Threads.@threads for kk in 1:Nk
            _transporte_k!(e, p, vx_o, kk)
        end
    else
        for kk in 1:Nk
            _transporte_k!(e, p, vx_o, kk)
        end
    end
    return nothing
end

"""
    fracao_agua_oleo(e, p, coluna) -> φ

Inferência da Eq. 9: `φ = Σ_k σ_k·(π/6)·d_k³`, média sobre as camadas de óleo da coluna
dada. `coluna = 0` devolve a média das `N_x−1` colunas à esquerda do vertedouro (a que se
compara com campo); `coluna = N_x`, a coluna à direita (conferência cruzada). **Redução
sequencial** — nunca paralela — para determinismo bit a bit (A.9).
"""
function fracao_agua_oleo(e::Estado, p::Params, coluna::Int)
    No, Nx, Nk = p.malha.n_oleo, p.malha.n_colunas, p.malha.n_gota
    cols = coluna == 0 ? (1:Nx-1) : (coluna:coluna)
    acc = 0.0
    ncell = 0
    for i in cols
        for j in 1:No
            s = 0.0
            for kk in 1:Nk                                  # soma sequencial
                s += e.sig[j, i, kk] * (π / 6) * p.d_gota[kk]^3
            end
            acc += s
            ncell += 1
        end
    end
    return ncell == 0 ? 0.0 : acc / ncell
end

# ===========================================================================
# CFL, regime permanente e o passo
# ===========================================================================

"""
    verificar_cfl(e, p, vx_o) -> (ok, dt_max)

CFL: `velocidade × Δt ≤ tamanho de célula`, nas duas direções. Devolve o `Δt` máximo
admissível; `ok = false` quando o `Δt` corrente o viola. O módulo **verifica a cada
passo** e nunca reduz `Δt` em silêncio (A.8): a violação vira estado de inviabilidade.
"""
function verificar_cfl(e::Estado, p::Params, vx_o::Float64)
    # Laços explícitos, e não `minimum(gen)`: a generator que captura `p` aloca ~32 B por
    # passo, e o critério de aceitação 8 é passo com ZERO alocação.
    dx = Inf
    for i in 1:p.malha.n_colunas
        dx = min(dx, _dx(p, i))
    end
    dy = Inf
    @inbounds for j in 1:p.malha.n_oleo
        dy = min(dy, e.yface[j + 1] - e.yface[j])
    end
    vy = 0.0
    @inbounds for kk in 1:p.malha.n_gota
        vy = max(vy, e.vy_k[kk])
    end
    dt_x = vx_o > 0 ? dx / vx_o : Inf
    dt_y = vy > 0 ? dy / vy : Inf
    dt_max = min(dt_x, dt_y)
    return (p.dt <= dt_max, dt_max)
end

"""
    passo!(e, p) -> (ok, dt_max)

Um passo de tempo fixo `Δt`, in-place e **sem alocar**. Ordem: níveis/pressão do passo
anterior → controladores (Eq. 16) → vazões (Eq. 6–8) → integra Eq. 1/2/4 → transporte
(Eq. 10–12) → CFL. `ok = false` (com `dt_max`) sinaliza violação de CFL — inviabilidade
como estado, nunca exceção.
"""
function passo!(e::Estado, p::Params)
    # 1. valores calculados no passo anterior (§2.3: e(t) usa o valor anterior)
    Hw, Hl, P, z, rho_g = niveis_e_pressao(p, e.v_w, e.v_l, e.n)

    # 2. controladores (Eq. 16) ou aberturas fixas. A válvula usa a saída SATURADA; a
    #    memória `f(t−1)` guarda a saturada ou não conforme a chave de anti-windup (A.5).
    local ab_o, ab_w, ab_g
    if p.malha_fechada
        # Erros nas unidades em que os ganhos da Tabela 3 são publicados: pressão em kPa
        # (KPP em kPa⁻¹), níveis em m (KP em m⁻¹). É a leitura que mantém 8/2/10 e 4/50/25
        # utilizáveis como impressos; a variável de pressão do artigo é kPa.
        #
        # AÇÃO REVERSA (medido − setpoint), e não (setpoint − medido) do texto: as três
        # válvulas são de SAÍDA — abrir a de gás BAIXA a pressão, abrir a de nível BAIXA o
        # nível (confirmado numericamente). Com ganho positivo publicado e o erro do texto
        # o laço seria realimentação POSITIVA e a pressão dispararia; a direção reversa é o
        # que a Figura 3 (logic do PI, imagem no PDF) codifica e o que estabiliza o laço.
        eP  = (P - p.sp.p) / 1000.0
        eOl = Hl - p.sp.h_oleo
        eWl = Hw - p.sp.h_agua
        sat_g, mem_g = pi_incremental(e.ab_gas,  eP,  e.e_p_prev,
                                      p.ganhos.kp_p,  p.ganhos.ki_p,  p.dt;
                                      guardar_saturado = p.guardar_saturado)
        sat_o, mem_o = pi_incremental(e.ab_oleo, eOl, e.e_ol_prev,
                                      p.ganhos.kp_ol, p.ganhos.ki_ol, p.dt;
                                      guardar_saturado = p.guardar_saturado)
        sat_w, mem_w = pi_incremental(e.ab_agua, eWl, e.e_wl_prev,
                                      p.ganhos.kp_wl, p.ganhos.ki_wl, p.dt;
                                      guardar_saturado = p.guardar_saturado)
        e.ab_gas, e.ab_oleo, e.ab_agua = mem_g, mem_o, mem_w
        e.e_p_prev, e.e_ol_prev, e.e_wl_prev = eP, eOl, eWl
        ab_o, ab_w, ab_g = sat_o, sat_w, sat_g
    else
        ab_o = clamp(e.ab_oleo, 0.0, 1.0)
        ab_w = clamp(e.ab_agua, 0.0, 1.0)
        ab_g = clamp(e.ab_gas, 0.0, 1.0)
    end

    # 3. vazões de saída
    Qo, Qw, Qg = vazoes_saida(p, P, rho_g, ab_o, ab_w, ab_g)

    # 4. integra níveis e mols (Eq. 1, 2, 4)
    v_w_novo = e.v_w + (p.ent.q_agua_in - Qw) * p.dt
    v_l_novo = e.v_l + (p.ent.q_agua_in + p.ent.q_oleo_in - Qw - Qo) * p.dt
    n_novo   = e.n + (p.ent.q_gas_in - Qg) * rho_g * p.dt / p.fluido.M

    # 5. transporte disperso (Eq. 10–12) — usa a geometria do passo corrente
    _remalhar!(e, p, Hw, Hl)
    _velocidades_gota!(e, p)
    A_oleo = area_segmento(Hl, p.geo.d_vaso) - area_segmento(Hw, p.geo.d_vaso)
    dV_o = (v_l_novo - v_w_novo) - (e.v_l - e.v_w)
    vx_o = A_oleo > 0 ? (Qo + dV_o / p.dt) / A_oleo : 0.0
    vx_o = max(vx_o, 0.0)
    _transporte!(e, p, vx_o)
    e.sig, e.sig_buf = e.sig_buf, e.sig          # troca de buffers, sem alocar

    # 6. CFL do passo corrente
    ok, dt_max = verificar_cfl(e, p, vx_o)

    # 7. avança
    e.v_w, e.v_l, e.n = v_w_novo, v_l_novo, n_novo
    e.t += p.dt
    e.passo += 1
    return (ok, dt_max)
end

# ===========================================================================
# Forma f!(du,u,p,t) e o integrador de Euler — para o oráculo (H.1)
# ===========================================================================

"Empacota o estado contínuo (V_w, V_l, n, σ) num vetor plano — para o oráculo de EDO."
function empacotar(e::Estado)
    return vcat(e.v_w, e.v_l, e.n, vec(e.sig))
end

"Desempacota `u` de volta em (V_w, V_l, n) e escreve σ em `e.sig`."
function desempacotar!(e::Estado, u::AbstractVector{Float64})
    e.v_w, e.v_l, e.n = u[1], u[2], u[3]
    No, Nx, Nk = size(e.sig)
    @inbounds for idx in 1:No*Nx*Nk
        e.sig[idx] = u[3 + idx]
    end
    return nothing
end

"""
    rhs!(du, u, params_estado, t) -> nothing

Derivada do estado contínuo em `f!(du,u,p,t)` — **aberturas fixas**, sem controlador (o
PI discreto é a camada de passo fixo, A.9/H.1). `params_estado` é `(p::Params, e::Estado)`
(o `e` só como work buffer). Puro e sem estado global; a troca por `OrdinaryDiffEq.jl`
fica reduzida a uma linha. É o RHS que o oráculo `OrdinaryDiffEqTsit5` integra para provar
que o Euler de passo fixo em `Δt = 0,5 s` está convergido.
"""
function rhs!(du::AbstractVector{Float64}, u::AbstractVector{Float64}, pe, t::Float64)
    p, e = pe
    desempacotar!(e, u)
    Hw, Hl, P, z, rho_g = niveis_e_pressao(p, e.v_w, e.v_l, e.n)
    Qo, Qw, Qg = vazoes_saida(p, P, rho_g, e.ab_oleo, e.ab_agua, e.ab_gas)
    du[1] = p.ent.q_agua_in - Qw
    du[2] = p.ent.q_agua_in + p.ent.q_oleo_in - Qw - Qo
    du[3] = (p.ent.q_gas_in - Qg) * rho_g / p.fluido.M
    _remalhar!(e, p, Hw, Hl)
    _velocidades_gota!(e, p)
    A_oleo = area_segmento(Hl, p.geo.d_vaso) - area_segmento(Hw, p.geo.d_vaso)
    vx_o = A_oleo > 0 ? max(Qo / A_oleo, 0.0) : 0.0
    No, Nx, Nk = p.malha.n_oleo, p.malha.n_colunas, p.malha.n_gota
    @inbounds for kk in 1:Nk, i in 1:Nx, j in 1:No
        dx = _dx(p, i)
        sig_ij = e.sig[j, i, kk]
        sig_esq = i == 1 ? e.sigin_k[kk] : e.sig[j, i - 1, kk]
        dsig_x = vx_o * (sig_esq - sig_ij) / dx
        sig_cima = j == No ? 0.0 : e.sig[j + 1, i, kk]
        fluxo = e.wbound[j + 1] * sig_cima - e.wbound[j] * sig_ij
        dsig_y = e.aface[j] > 0 ? e.vy_k[kk] * fluxo / e.aface[j] : 0.0
        du[3 + ((kk - 1) * Nx + (i - 1)) * No + j] = dsig_x + dsig_y
    end
    return nothing
end

# ===========================================================================
# Simulação, regime permanente e métricas
# ===========================================================================

"Trajetória registrada da simulação (cadência independente de `Δt`)."
struct Trajetoria
    t::Vector{Float64}
    P::Vector{Float64}         # Pa
    H_agua::Vector{Float64}    # m
    H_oleo::Vector{Float64}    # m
    ab_oleo::Vector{Float64}
    ab_agua::Vector{Float64}
    ab_gas::Vector{Float64}
    q_oleo::Vector{Float64}    # m³/s
    q_agua::Vector{Float64}
    q_gas::Vector{Float64}
    phi_esq::Vector{Float64}
    phi_dir::Vector{Float64}
    folga_cfl::Vector{Float64} # dt_max/dt no passo do registro
    carimbos::Vector{String}
end

"Estado de inviabilidade devolvido (nunca exceção): CFL violado, com o `Δt` máximo."
struct Inviabilidade
    mensagem::String
    dt_max::Float64
    t::Float64
end

"""
    simular(p; v_w0, v_l0, p0) -> Trajetoria | Inviabilidade

Roda a simulação por `horizonte`, registrando a cada `cadencia`. Devolve a
[`Trajetoria`](@ref) ou uma [`Inviabilidade`](@ref) se o CFL for violado. As gotículas de
entrada (feed) são semeadas em `sigin_k` a partir de `φ_água,óleo,in` e da distribuição
da Figura 4, convertidas a densidade numérica: `σ_in,k = φ_in·frac_k / ((π/6)·d_k³)`.
"""
function simular(p::Params; v_w0::Float64, v_l0::Float64, p0::Float64)
    e = construir_estado(p; v_w0, v_l0, p0)
    for kk in 1:p.malha.n_gota
        vol_k = (π / 6) * p.d_gota[kk]^3
        e.sigin_k[kk] = vol_k > 0 ? p.ent.phi_agua_oleo_in * p.frac_gota[kk] / vol_k : 0.0
    end

    nsteps = max(1, round(Int, p.horizonte / p.dt))
    cada = max(1, round(Int, p.cadencia / p.dt))
    T = Trajetoria(Float64[], Float64[], Float64[], Float64[], Float64[], Float64[],
                   Float64[], Float64[], Float64[], Float64[], Float64[], Float64[],
                   Float64[], String[])

    for carimbo in p.fluido.carimbos
        push!(T.carimbos, carimbo.propriedade * ": " * carimbo.detalhe)
    end

    for s in 1:nsteps
        ok, dt_max = passo!(e, p)
        if !ok
            return Inviabilidade(
                "CFL violado no passo $(e.passo): Δt = $(p.dt) s excede o máximo " *
                "admissível $(round(dt_max, digits = 3)) s. Reduza dt_passo ou refine a " *
                "malha.", dt_max, e.t)
        end
        if s % cada == 0 || s == nsteps
            Hw, Hl, P, z, rho_g = niveis_e_pressao(p, e.v_w, e.v_l, e.n)
            Qo, Qw, Qg = vazoes_saida(p, P, rho_g, e.ab_oleo, e.ab_agua, e.ab_gas)
            A_oleo = area_segmento(Hl, p.geo.d_vaso) - area_segmento(Hw, p.geo.d_vaso)
            vx = A_oleo > 0 ? max(Qo / A_oleo, 0.0) : 0.0
            _, cfl_max = verificar_cfl(e, p, vx)
            push!(T.t, e.t); push!(T.P, P)
            push!(T.H_agua, Hw); push!(T.H_oleo, Hl)
            push!(T.ab_oleo, e.ab_oleo); push!(T.ab_agua, e.ab_agua); push!(T.ab_gas, e.ab_gas)
            push!(T.q_oleo, Qo); push!(T.q_agua, Qw); push!(T.q_gas, Qg)
            push!(T.phi_esq, fracao_agua_oleo(e, p, 0))
            push!(T.phi_dir, fracao_agua_oleo(e, p, p.malha.n_colunas))
            push!(T.folga_cfl, cfl_max / p.dt)
        end
    end
    return T
end

"""
    regime_permanente(v, janela, dt_reg, eps) -> Bool

Estacionariedade por variação pico a pico dentro de uma janela móvel de `janela`
segundos abaixo de `eps` (A.7). Critério de estacionariedade, **não** de proximidade do
setpoint — em §3.2 a pressão estabiliza acima do alvo com a válvula saturada.
"""
function regime_permanente(v::AbstractVector{Float64}, janela::Float64, dt_reg::Float64,
                           eps::Float64)
    n = max(1, round(Int, janela / dt_reg))
    length(v) < n && return false
    jan = @view v[end-n+1:end]
    return (maximum(jan) - minimum(jan)) < eps
end

"Métricas de uma malha, calculadas da trajetória — não tocam na física (A.6)."
struct MetricaMalha
    sobressinal::Float64       # fração acima do degrau
    tempo_acomodacao::Float64  # s até entrar e ficar na faixa
    offset::Float64            # resíduo em relação ao setpoint
    iae::Float64               # integral do erro absoluto
end

"""
    metricas_malha(t, y, setpoint, y0; faixa) -> MetricaMalha

Sobressinal, tempo de acomodação, offset residual e IAE de uma resposta ao degrau, da
trajetória. `y0` é o valor de partida (regime anterior); `faixa` é a fração do degrau que
define acomodação (default 2 %). Função separada que **não toca na física**.
"""
function metricas_malha(t::AbstractVector{Float64}, y::AbstractVector{Float64},
                        setpoint::Float64, y0::Float64; faixa::Float64 = 0.02)
    degrau = setpoint - y0
    yfinal = y[end]
    offset = setpoint - yfinal
    sob = 0.0
    if degrau != 0
        pico = degrau > 0 ? maximum(y) : minimum(y)
        sob = max((pico - setpoint) / degrau, 0.0)
    end
    iae = 0.0
    for i in 2:length(t)
        iae += abs(setpoint - y[i]) * (t[i] - t[i - 1])
    end
    tol = abs(degrau) * faixa
    tacc = t[end]
    for i in length(t):-1:1
        if abs(y[i] - setpoint) > tol
            tacc = i < length(t) ? t[i + 1] : t[end]
            break
        end
        i == 1 && (tacc = t[1])
    end
    return MetricaMalha(sob, tacc, offset, iae)
end

# ===========================================================================
# Varredura de ganhos — o ganho grande do paralelismo (A.9)
# ===========================================================================

"""
    varredura_ganhos(p, kps, kis, qual; v_w0, v_l0, p0, sp_var, y0) -> Matrix{MetricaMalha}

Grade `(K_P, K_I)` de simulações independentes, `Threads.@threads` sobre a grade — cada
célula é uma simulação inteira. `qual` ∈ {:pressao, :oleo, :agua} diz qual malha varrer;
`sp_var` o setpoint dessa variável (para as métricas) e `y0` o valor de partida. As
reduções internas de cada simulação continuam sequenciais, então o resultado independe do
número de threads.
"""
function varredura_ganhos(p::Params, kps::AbstractVector{Float64},
                          kis::AbstractVector{Float64}, qual::Symbol;
                          v_w0::Float64, v_l0::Float64, p0::Float64,
                          sp_var::Float64, y0::Float64)
    M = Matrix{MetricaMalha}(undef, length(kps), length(kis))
    idx = vec([(a, b) for a in eachindex(kps), b in eachindex(kis)])
    Threads.@threads for lin in idx
        a, b = lin
        pl = _com_ganho(p, qual, kps[a], kis[b])
        r = simular(pl; v_w0, v_l0, p0)
        M[a, b] = if r isa Trajetoria
            y = qual === :pressao ? r.P : qual === :oleo ? r.H_oleo : r.H_agua
            metricas_malha(r.t, y, sp_var, y0)
        else
            MetricaMalha(NaN, NaN, NaN, NaN)   # inviável (CFL): métricas indefinidas
        end
    end
    return M
end

"Copia `p` trocando os ganhos da malha `qual`."
function _com_ganho(p::Params, qual::Symbol, kp::Float64, ki::Float64)
    g = p.ganhos
    ng = qual === :pressao ? Ganhos(kp, ki, g.kp_ol, g.ki_ol, g.kp_wl, g.ki_wl) :
         qual === :oleo    ? Ganhos(g.kp_p, g.ki_p, kp, ki, g.kp_wl, g.ki_wl) :
                             Ganhos(g.kp_p, g.ki_p, g.kp_ol, g.ki_ol, kp, ki)
    return Params(p.k, p.geo, p.malha, p.ent, ng, p.sp, p.fluido, p.d_gota, p.frac_gota,
                  p.dt, p.horizonte, p.cadencia, p.malha_fechada, p.ab_oleo, p.ab_agua,
                  p.ab_gas, p.guardar_saturado, p.janela, p.paralelo)
end

end # module SongDynamics
