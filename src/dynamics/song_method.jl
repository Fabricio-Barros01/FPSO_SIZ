"""
Adaptador do módulo dinâmico — a ponte entre o TOML e a física isolada de `dynamics/`.

Este arquivo entra **depois** de `config.jl`, `interfaces.jl` e do registro: é ele, e não
a física, que lê a configuração, cita `ParameterSpec` e faz a **conversão de unidades num
ponto só** (°C→K, m³/h→m³/s, kPa→Pa, µm→m, cP→Pa·s). `SongDynamics` e `Propriedades`
continuam sem conhecer nada disto — a fronteira é aqui, como em `analysis/pinch_method.jl`.

Registra um par equipamento/método (`SeparadorDinamico`/`SongDinamico`) **fora da família
dos vasos**: `SongDinamico <: AbstractSizingMethod`, não `AbstractVesselMethod`. Ele existe
só para que o box do catálogo **resolva no registro** (guarda `architecture.jl:252`) e o
formulário se monte pelo `ParameterSpec` como o de qualquer outro método. Não dimensiona:
`stream_keys` é vazio (sem entradas de corrente), e `size_equipment` devolve estado
inviável dizendo para usar a tela dinâmica. O caminho de servir do box dinâmico **desvia
do fluxo de dimensionamento** (sem `AppState`, sem `dimensionar!`): a tela consome
`parametros_dinamico`, `simular_dinamico` e `canais_dinamico` por rotas próprias.
"""

const _DYN_CONFIG = ("dynamics", "song.toml")

"O TOML do módulo dinâmico."
config_dinamico() = load_config(_DYN_CONFIG...)

"""
    parametros_dinamico() -> Vector{ParameterSpec}

Descritores de formulário do módulo dinâmico (operação, geometria, malha, passo, ganhos,
setpoints, aberturas e overrides de propriedade). É o que a tela itera — nenhum nome de
grandeza escrito na interface.
"""
parametros_dinamico() = parameter_specs(config_dinamico())

"Dicionário `key => default` do módulo dinâmico."
valores_default_dinamico() = defaults(parametros_dinamico())

"""
Um canal de série temporal declarado pelo método (C.2): rótulo, unidade e eixo. A tela
itera sobre isto para montar o gráfico, sem citar nenhuma grandeza pelo nome.
"""
struct CanalSerie
    campo::Symbol      # o campo da Trajetoria
    label::String
    unidade::String
    eixo::Symbol       # :pressao | :nivel | :abertura | :vazao | :fracao | :cfl
end

"""
    canais_dinamico() -> Vector{CanalSerie}

Os canais mínimos (C.4): pressão, níveis de água e óleo, as três aberturas, as três
vazões de saída, `φ` à esquerda e à direita, e a folga de CFL.
"""
canais_dinamico() = CanalSerie[
    CanalSerie(:P,       "Pressão",              "kPa",   :pressao),
    CanalSerie(:H_agua,  "Nível de água",        "m",     :nivel),
    CanalSerie(:H_oleo,  "Nível de óleo",        "m",     :nivel),
    CanalSerie(:ab_oleo, "Abertura — óleo",      "–",     :abertura),
    CanalSerie(:ab_agua, "Abertura — água",      "–",     :abertura),
    CanalSerie(:ab_gas,  "Abertura — gás",       "–",     :abertura),
    CanalSerie(:q_oleo,  "Vazão de saída — óleo", "m³/h", :vazao),
    CanalSerie(:q_agua,  "Vazão de saída — água", "m³/h", :vazao),
    CanalSerie(:q_gas,   "Vazão de saída — gás",  "m³/h", :vazao),
    CanalSerie(:phi_esq, "Água no óleo (esq.)",  "–",     :fracao),
    CanalSerie(:phi_dir, "Água no óleo (dir.)",  "–",     :fracao),
    CanalSerie(:folga_cfl, "Folga de CFL",       "×",     :cfl),
]

# ---------------------------------------------------------------------------
# Montagem dos parâmetros da física a partir dos valores do formulário
# ---------------------------------------------------------------------------

"`v` (cP) como Pa·s, ou `NaN` (usar correlação) quando `v ≤ 0`."
_override_visc(v) = v > 0 ? v * 1e-3 : NaN
"`v` como override, ou `NaN` (usar correlação) quando `v ≤ 0`."
_override(v) = v > 0 ? float(v) : NaN

"""
    construir_params_dinamico(valores; malha_fechada, paralelo, guardar_saturado) -> Params

Monta os `SongDynamics.Params` a partir do dicionário do formulário (mesclado com os
defaults), fazendo toda a conversão de unidades para SI. `malha_fechada = false` reproduz
§3.1 (aberturas fixas); `true`, §3.2 (as três malhas).
"""
function construir_params_dinamico(valores::AbstractDict;
                                   malha_fechada::Bool = true,
                                   paralelo::Bool = false,
                                   guardar_saturado::Bool = true)
    cfg = config_dinamico()
    p = with_defaults(parametros_dinamico(), valores)
    k = constants(cfg)

    K = SongDynamics.Constantes(
        float(k[:r_gas]), float(k[:gravidade]), float(k[:isa_coeficiente]),
        float(k[:fp]), float(k[:xt]), float(k[:fk]),
        float(k[:stokes_divisor]), float(k[:intermediario_c]), float(k[:newton_c]),
        float(k[:d1_c]), float(k[:d2_c]), float(k[:alfa_limiar_gas]),
        float(k[:alfa_fator]), float(k[:cv_oleo]), float(k[:cv_agua]), float(k[:cv_gas]))

    geo = SongDynamics.Geometria(p[:d_vaso], p[:l_esquerda], p[:l_total],
                                 p[:h_vertedouro], p[:h_tampo])
    malha = SongDynamics.Malha(round(Int, p[:n_colunas]), round(Int, p[:n_oleo]),
                               round(Int, p[:n_agua]), length(get(cfg, "gota", Any[])))

    T = p[:temperatura] + 273.15
    ent = SongDynamics.Entradas(T, p[:q_oleo_in] / 3600, p[:q_agua_in] / 3600,
                                p[:q_gas_in] / 3600, p[:p_jusante] * 1000,
                                p[:phi_agua_oleo_in])

    ganhos = SongDynamics.Ganhos(p[:kp_p], p[:ki_p], p[:kp_ol], p[:ki_ol],
                                 p[:kp_wl], p[:ki_wl])
    sp = SongDynamics.Setpoints(p[:sp_pressao] * 1000, p[:sp_oleo], p[:sp_agua])

    # composição do gás → SI
    comps = Propriedades.Componente[]
    for c in get(cfg, "componente", Any[])
        push!(comps, Propriedades.Componente(String(c["nome"]), float(c["y"]),
                     float(c["m_kg_mol"]), float(c["tc_c"]) + 273.15,
                     float(c["pc_kpa"]) * 1000, float(c["omega"])))
    end

    # distribuição de gotícula → SI, fração normalizada
    d_gota = Float64[]
    frac = Float64[]
    for g in get(cfg, "gota", Any[])
        push!(d_gota, float(g["d_um"]) * 1e-6)
        push!(frac, float(g["frac"]))
    end
    s = sum(frac)
    s > 0 && (frac ./= s)

    P_ref = p[:sp_pressao] * 1000
    fluido = Propriedades.construir_fluido(comps, T, K.r_gas;
                rho_oleo = p[:rho_oleo], rho_agua = p[:rho_agua], P_ref = P_ref,
                z_fixo = _override(p[:z_fixo]),
                mu_oleo = _override_visc(p[:mu_oleo_override]),
                mu_agua = _override_visc(p[:mu_agua_override]),
                mu_gas  = _override_visc(p[:mu_gas_override]))

    return SongDynamics.Params(K, geo, malha, ent, ganhos, sp, fluido, d_gota, frac,
        p[:dt_passo], p[:horizonte], p[:cadencia_registro], malha_fechada,
        p[:ab_oleo], p[:ab_agua], p[:ab_gas], guardar_saturado, p[:janela_regime],
        paralelo)
end

"""
    estado_inicial_dinamico(pr, valores) -> (v_w0, v_l0, p0)

Condições iniciais em SI. `H_w0` é o nível de água inicial; `H_l0` é o nível de líquido
total inicial, tomado como o maior entre o setpoint de óleo, a altura do vertedouro e
`H_w0` + 2 cm — garantindo `H_l0 > H_w0` (o óleo é uma camada sobre a água). Ver o
cabeçalho de `song.jl` sobre a reconciliação dos referenciais esquerda/direita.
"""
function estado_inicial_dinamico(pr::SongDynamics.Params, valores::AbstractDict)
    p = with_defaults(parametros_dinamico(), valores)
    g = pr.geo
    Hw0 = p[:sp_agua]
    Hl0 = max(p[:sp_oleo], g.h_vertedouro, Hw0 + 0.02)
    Hl0 = min(Hl0, g.d_vaso - 1e-3)
    v_w0 = SongDynamics.volume_nivel(Hw0, g.d_vaso, g.l_esquerda, g.h_tampo)
    v_l0 = SongDynamics.volume_nivel(Hl0, g.d_vaso, g.l_esquerda, g.h_tampo)
    p0 = p[:sp_pressao] * 1000
    return (v_w0, v_l0, p0)
end

"""
    simular_dinamico(valores; malha_fechada, paralelo, guardar_saturado)
        -> Trajetoria | Inviabilidade

Roda o simulador dinâmico a partir dos valores do formulário. `malha_fechada = false`
reproduz §3.1; `true`, §3.2. Nunca lança: inviabilidade (CFL) volta como estado.
"""
function simular_dinamico(valores::AbstractDict; malha_fechada::Bool = true,
                          paralelo::Bool = false, guardar_saturado::Bool = true)
    pr = construir_params_dinamico(valores; malha_fechada, paralelo, guardar_saturado)
    v_w0, v_l0, p0 = estado_inicial_dinamico(pr, valores)
    return SongDynamics.simular(pr; v_w0, v_l0, p0)
end

# ---------------------------------------------------------------------------
# Registro — um par equipamento/método fora da família dos vasos (Entrega C.1)
# ---------------------------------------------------------------------------

"O equipamento do box dinâmico. Não é vaso; não produz `VesselConstraints`."
struct SeparadorDinamico <: AbstractEquipment end
method_id(::SeparadorDinamico) = :separador_dinamico
label(::SeparadorDinamico) = "Separador Trifásico — Dinâmico"

"""
O método do box dinâmico. `AbstractSizingMethod`, **não** `AbstractVesselMethod` — não
tem grade de diâmetro, teto de decantação nem esbeltez. Serve para o box resolver no
registro e o formulário montar-se pelo `ParameterSpec`; a simulação corre por
[`simular_dinamico`](@ref), não por `size_equipment`.
"""
struct SongDinamico <: AbstractSizingMethod end
method_id(::SongDinamico) = :song_dinamico
applies_to(::SongDinamico) = SeparadorDinamico()
method_config(::SongDinamico) = config_dinamico()
label(::SongDinamico) = config_label(config_dinamico(), "Song et al. (2023)")
parameters(::SongDinamico) = parametros_dinamico()

# Sem entradas de corrente: as vazões do dinâmico são campos próprios do TOML, não a
# `StreamState` comum. `stream_keys` vazio faz `stream_parameters(m)` devolver vetor
# vazio, e a tela dinâmica não desenha nenhuma caixa de corrente.
stream_keys(::SongDinamico) = ()

# O dinâmico não varre eixo nenhum (não dimensiona): sem colunas de varredura. Definido
# porque a guarda de vocabulário de `smoke.jl` chama `sweep_columns(m)` sobre TODO método
# registrado, e não há default genérico.
sweep_columns(::SongDinamico) = SweepColumn[]

"""
    size_equipment(::SeparadorDinamico, ::SongDinamico, stream, params) -> SizingResult

O dinâmico não dimensiona um vaso — ele simula no tempo. Devolve estado inviável (nunca
lança) apontando para a tela dinâmica, para o caso de o fluxo genérico de dimensionamento
alcançar este método por engano.
"""
size_equipment(::SeparadorDinamico, ::SongDinamico, stream, params) =
    infeasible(:song_dinamico,
        "O separador dinâmico não dimensiona um vaso: ele simula no tempo. Use a tela " *
        "dinâmica (Simular), não Dimensionar.")
