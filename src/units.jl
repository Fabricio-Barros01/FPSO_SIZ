"""
Conversões de unidades e constantes físicas.

Regra do projeto: **toda** conversão numérica mora aqui. O core guarda tudo em SI
(`m³/s`, `kg/m³`, `Pa·s`, `Pa`, `K`); as correlações de Stewart & Arnold trabalham
nas unidades em que foram publicadas (`mm`, `m`, `m³/h`, `cP`, `kPa`, `K`, `µm`, `min`).
A conversão acontece num único ponto, em `field_units`, e nunca espalhada no cálculo.
"""
module Units

export INCH_M, FOOT_M, BARREL_M3, PSI_KPA, LB_KG, CUFT_M3
export m3s_to_m3h, m3h_to_m3s, pas_to_cp, cp_to_pas, pa_to_kpa, kpa_to_pa
export celsius_to_kelvin, kelvin_to_celsius, mm_to_m, m_to_mm
export api_to_density, density_to_api, specific_gravity
export liquid_capacity_coefficient, RHO_WATER_REF
export G_STANDARD, EPS0, hydraulic_power_kw

# ---------------------------------------------------------------------------
# Constantes de conversão (exatas por definição, salvo nota)
# ---------------------------------------------------------------------------
const INCH_M    = 0.0254              # m/in           (exato)
const FOOT_M    = 0.3048              # m/ft           (exato)
const BARREL_M3 = 0.158987294928      # m³/bbl         (exato: 42 gal US)
const PSI_KPA   = 6.894757293168361   # kPa/psi
const LB_KG     = 0.45359237          # kg/lb          (exato)
const CUFT_M3   = 0.028316846592      # m³/ft³         (exato)

"""
Aceleração da gravidade padrão (ISO 80000-3), em m/s².

Não é o valor que a bomba usa: Moran (*Pump Sizing*, CEP 2016) declara `g = 9,81` ao
definir a perda localizada, e o método segue a fonte — a diferença de 0,03 % não move
nenhum diâmetro nominal. Fica aqui porque é a referência contra a qual esse `9,81` se
justifica, e porque um método futuro que não tenha fonte própria deve usar este.
"""
const G_STANDARD = 9.80665            # m/s²

"""
Permissividade elétrica do vácuo, em F/m (CODATA 2018).

Constante física, e não coeficiente de correlação: por isso mora aqui e não no TOML de
nenhum método. Entra na atração de dipolo entre gotículas de água num campo elétrico —
ver `src/sizing/treater/electrostatic.jl`.
"""
const EPS0 = 8.8541878128e-12         # F/m

"Densidade da água usada como referência na Eq. 12 (água doce, condição padrão)."
const RHO_WATER_REF = 1000.0          # kg/m³

# ---------------------------------------------------------------------------
# Conversões simples
# ---------------------------------------------------------------------------
m3s_to_m3h(q) = q * 3600.0
m3h_to_m3s(q) = q / 3600.0
pas_to_cp(mu)  = mu * 1000.0
cp_to_pas(mu)  = mu / 1000.0
pa_to_kpa(p)   = p / 1000.0
kpa_to_pa(p)   = p * 1000.0
celsius_to_kelvin(t) = t + 273.15
kelvin_to_celsius(t) = t - 273.15
mm_to_m(x) = x / 1000.0
m_to_mm(x) = x * 1000.0

# ---------------------------------------------------------------------------
# Densidade / grau API
# ---------------------------------------------------------------------------
"""
    api_to_density(api; rho_water = RHO_WATER_REF)

Eq. (12) de Alves & Komesu: `ρ_l = ρ_w · 141,5 / (131,5 + °API)`.
"""
api_to_density(api; rho_water = RHO_WATER_REF) = rho_water * 141.5 / (131.5 + api)

"Inversa de [`api_to_density`](@ref)."
density_to_api(rho; rho_water = RHO_WATER_REF) = 141.5 * rho_water / rho - 131.5

"Densidade relativa (adimensional) em relação à água de referência."
specific_gravity(rho; rho_water = RHO_WATER_REF) = rho / rho_water

"""
    hydraulic_power_kw(rho, q_m3h, h_m, eta; g) -> kW

Potência de eixo de uma bomba centrífuga: `P = ρ·g·Q·H/(3,6×10⁶·η)`, com `Q` em m³/h e
`H` em metros de coluna do próprio fluido — a forma que Moran publica.

O `3,6×10⁶` é conversão de unidade, não coeficiente empírico: são os 3600 s/h que
levam `Q` a m³/s e os 1000 W/kW que levam o resultado a quilowatt. Por isso mora aqui,
e não no TOML do método junto das constantes das correlações — a regra do projeto é que
TOML guarda premissa revisável, e esta não é.

`eta` é o rendimento; o artigo recomenda 0,7 quando ele não for conhecido, e adverte
que se deve **arredondar para cima**, porque o elétrico prefere ouvir depois que a
potência caiu do que que subiu.
"""
hydraulic_power_kw(rho, q_m3h, h_m, eta; g = G_STANDARD) =
    rho * g * q_m3h * h_m / (3.6e6 * eta)

# ---------------------------------------------------------------------------
# Coeficiente da capacidade de líquido (Eq. 22)
# ---------------------------------------------------------------------------
"""
    liquid_capacity_coefficient()

Coeficiente da Eq. (22) — `d²·Leff = C · (tr_o·Q_o + tr_w·Q_w)` — para
`d` em mm, `Leff` em m, `tr` em min e `Q` em m³/h.

**Por que este valor e não o `4,12×10⁴` impresso no artigo.** A forma original de
Stewart & Arnold (2008) em unidades de campo é

    d[in]² · Leff[ft] = 1,42 · (tr[min] · Q[BPD])

Convertendo apenas as unidades:

    d[in]²·Leff[ft] = d[mm]²·Leff[m] / (25,4² × 0,3048) = d²Leff / 196,6448
    Q[BPD]          = Q[m³/h] × 24 / 0,158987294928     = Q × 150,95575
    ⇒ C = 196,6448 × 1,42 × 150,95575 = 4,2152×10⁴

O `4,12×10⁴` impresso em Alves & Komesu (2025) é inconsistente com a **própria
Tabela 3 do artigo**: as seis linhas publicadas dão `d²·Leff ≈ 5,2152×10⁸`, ou seja
um coeficiente implícito de `4,2004×10⁴`. O valor derivado acima reproduz a Tabela 3
com 0,35 % de desvio; o `4,12×10⁴` erra 1,9 %. Tratamos o `4,12` como erro
tipográfico. Ver `test/units.jl` e `test/golden_alves_komesu.jl`.
"""
function liquid_capacity_coefficient()
    lhs = (INCH_M * 1000.0)^2 * FOOT_M      # mm²·m por (in²·ft)
    rhs = 24.0 / BARREL_M3                  # BPD por (m³/h)
    return lhs * 1.42 * rhs
end

end # module Units
