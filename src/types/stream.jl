"""
`StreamState` — a descrição da corrente na entrada de um equipamento.

É o **adaptador comum** do projeto: tanto a entrada manual de propriedades quanto o
flash a partir da composição produzem um `StreamState`, e todo método de
dimensionamento consome só isto. É o que permitirá, no 2º plano, ligar o vaso flash
como *fonte* dos separadores sem tocar no código de dimensionamento.

Tudo em SI.
"""

"Propriedades de uma fase, em SI."
struct PhaseProps
    volumetric_flow::Float64   # m³/s
    density::Float64           # kg/m³
    viscosity::Float64         # Pa·s
end

"""
    StreamState(; oil, water, gas, pressure, temperature, z_factor)

Corrente trifásica em SI: `pressure` em Pa, `temperature` em K, `z_factor`
adimensional (fator de compressibilidade do gás).
"""
struct StreamState
    oil::PhaseProps
    water::PhaseProps
    gas::PhaseProps
    pressure::Float64          # Pa
    temperature::Float64       # K
    z_factor::Float64
end

"""
    stream_from_field(; q_oil_m3h, q_water_m3h, q_gas_m3h,
                        rho_oil, rho_water, rho_gas,
                        mu_oil_cp, mu_water_cp, mu_gas_cp,
                        p_kpa, t_celsius, z)

Constrói um [`StreamState`](@ref) a partir das unidades de engenharia em que os dados
de projeto normalmente chegam (as mesmas da Tabela 1 de Alves & Komesu). Densidades
em kg/m³.
"""
function stream_from_field(; q_oil_m3h, q_water_m3h, q_gas_m3h,
                             rho_oil, rho_water, rho_gas,
                             mu_oil_cp, mu_water_cp, mu_gas_cp,
                             p_kpa, t_celsius, z)
    StreamState(
        PhaseProps(Units.m3h_to_m3s(q_oil_m3h),   rho_oil,   Units.cp_to_pas(mu_oil_cp)),
        PhaseProps(Units.m3h_to_m3s(q_water_m3h), rho_water, Units.cp_to_pas(mu_water_cp)),
        PhaseProps(Units.m3h_to_m3s(q_gas_m3h),   rho_gas,   Units.cp_to_pas(mu_gas_cp)),
        Units.kpa_to_pa(p_kpa),
        Units.celsius_to_kelvin(t_celsius),
        z,
    )
end

"""
Chaves canônicas que descrevem a corrente num caso. Tudo o que **não** estiver aqui é
passado adiante como parâmetro do método de dimensionamento.

Os descritores correspondentes (rótulo, unidade, faixa) vivem em `config/stream.toml`.
"""
const STREAM_KEYS = (:q_oil, :q_water, :q_gas,
                     :rho_oil, :rho_water, :rho_gas,
                     :mu_oil, :mu_water, :mu_gas,
                     :pressure, :temperature, :z)

"""
    stream_from_case(vals) -> StreamState

Constrói a corrente a partir do dicionário de um caso já expandido (ver
`FPSOSiz.expand`). Espera as chaves de [`STREAM_KEYS`](@ref) nas unidades de
engenharia declaradas em `config/stream.toml`.
"""
function stream_from_case(vals::AbstractDict)
    missing_keys = [k for k in STREAM_KEYS if !haskey(vals, k)]
    isempty(missing_keys) ||
        throw(ArgumentError("caso sem as entradas de corrente: " *
                            join(missing_keys, ", ")))
    return stream_from_field(
        q_oil_m3h   = vals[:q_oil],
        q_water_m3h = vals[:q_water],
        q_gas_m3h   = vals[:q_gas],
        rho_oil     = vals[:rho_oil],
        rho_water   = vals[:rho_water],
        rho_gas     = vals[:rho_gas],
        mu_oil_cp   = vals[:mu_oil],
        mu_water_cp = vals[:mu_water],
        mu_gas_cp   = vals[:mu_gas],
        p_kpa       = vals[:pressure],
        t_celsius   = vals[:temperature],
        z           = vals[:z],
    )
end

"""
    field_units(s::StreamState)

Único ponto de conversão SI → unidades das correlações de Stewart & Arnold.
Devolve uma `NamedTuple` com vazões em m³/h, viscosidades em cP, pressão em kPa,
temperatura em K e densidades relativas.

Nenhuma outra função do módulo de dimensionamento deve converter unidades.
"""
function field_units(s::StreamState)
    (; q_o   = Units.m3s_to_m3h(s.oil.volumetric_flow),
       q_w   = Units.m3s_to_m3h(s.water.volumetric_flow),
       q_g   = Units.m3s_to_m3h(s.gas.volumetric_flow),
       rho_o = s.oil.density,
       rho_w = s.water.density,
       rho_g = s.gas.density,
       mu_o  = Units.pas_to_cp(s.oil.viscosity),
       mu_w  = Units.pas_to_cp(s.water.viscosity),
       mu_g  = Units.pas_to_cp(s.gas.viscosity),
       sg_o  = Units.specific_gravity(s.oil.density),
       sg_w  = Units.specific_gravity(s.water.density),
       p_kpa = Units.pa_to_kpa(s.pressure),
       t_k   = s.temperature,
       z     = s.z_factor)
end
