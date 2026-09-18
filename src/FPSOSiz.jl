"""
    FPSOSiz

Dimensionamento de equipamentos de processamento primário de FPSO pelo modelo
semiempírico de Stewart & Arnold (2008).

O core roda **headless**: não depende de nenhuma biblioteca de GUI. A interface vive em
`app/` e depende deste módulo, nunca o contrário. `test/architecture.jl` garante isso.

# Uso rápido

```julia
using FPSOSiz

# caso único, com os dados da Tabela 1 de Alves & Komesu (2025)
vals = FPSOSiz.default_case_values()
res  = FPSOSiz.size_equipment(Separator(), StewartArnold(),
                              FPSOSiz.stream_from_case(vals), vals)
res.diameter_mm, res.sr        # (5550.0, 4.08…) — grade default 3000:150:8000


# multi-caso: um vaso que atende os dois
cases = CaseSet([
    Case("Mid Life",  vals),
    Case("Late Life", merge(vals, Dict(:q_water => Interval(1025.8, 1400.0)))),
])
env = FPSOSiz.size_envelope(Separator(), StewartArnold(), cases)
env.diameter_mm, env.driver_case
```
"""
module FPSOSiz

using Printf
using TOML

include("units.jl")
using .Units

# Alvos de energia de uma REDE de correntes — outra pergunta que a de dimensionar um
# equipamento, e por isso um módulo à parte. Está aqui, e não lá embaixo junto do
# trocador, porque a posição é a prova de pureza: incluído antes de `interfaces.jl`,
# ele não tem como citar `ParameterSpec`, `AbstractSizingMethod` ou `Case` — nenhum
# deles existe ainda. Ciclo de import não tem por onde nascer.
include("analysis/pinch.jl")
using .PinchAnalysis

# Módulo dinâmico do separador (Song 2023) — subapp isolado, na MESMA posição de prova de
# pureza do pinch: incluído antes de `interfaces.jl`, não tem como citar `ParameterSpec`,
# `AbstractSizingMethod`, `field_units` nem nada de `src/sizing/` — eles não existem
# ainda. `propriedades.jl` (Entrega B) antes de `song.jl` (Entrega A), que dele depende.
# `test/architecture.jl` fixa esta ordem. O adaptador de box entra lá embaixo, depois de
# `config.jl` e do registro, como o de pinch.
include("dynamics/propriedades.jl")
using .Propriedades
include("dynamics/song.jl")
using .SongDynamics

include("interfaces.jl")
include("registry.jl")

# O contrato genérico método ↔ motor: o que o motor pede sem saber o que é um vaso.
include("engine/contract.jl")

include("types/results.jl")
include("types/stream.jl")
include("types/cases.jl")

# A camada DOCUMENTAL do contrato: quais equações o método usa, como elas se escrevem e
# o que se verifica. Entra aqui porque precisa de `AbstractSizingMethod` (interfaces) e
# de `CalcTrace` (results), e de mais nada — é puro dado/texto, sem dependência nova, e
# por isso não toca na guarda de duas dependências de `test/architecture.jl`.
include("memorial.jl")

# depois dos tipos: o carregador de casos constrói `Case`
include("config.jl")

# A família dos vasos: o contrato acima preenchido para quem varre diâmetro.
include("sizing/constraints.jl")

include("sizing/separator/beta.jl")
include("sizing/separator/drag.jl")
# Bloco de capacidade de gás: idêntico nos dois vasos, então mora fora de ambos.
include("sizing/gas_capacity.jl")
include("sizing/separator/stewart_arnold.jl")
# O memorial documental do separador. Separado do método por tamanho — ver o cabeçalho
# do arquivo. Depois dele, porque despacha em `StewartArnold`.
include("memorial_specs/stewart_arnold.jl")
include("sizing/knockout/two_phase.jl")
include("memorial_specs/stewart_arnold_2f.jl")
# Terceiro vaso da família: sem fase gasosa, e com a generalização de §4.9.4-4.9.6.
include("sizing/treater/electrostatic.jl")
include("memorial_specs/arnold_electrostatic.jl")

# Os dois que NÃO são vasos. Nenhum dos dois produz `VesselConstraints`, nenhum dos dois
# tem esbeltez, e é por isso que estão aqui: o contrato de `engine/contract.jl` só vale o
# que promete se alguém de fora da família dos vasos o preencher.
include("sizing/pump/hydraulics.jl")
include("sizing/pump/moran.jl")
include("memorial_specs/moran.jl")
# Coeficiente do lado do casco: física de feixe, e por isso fora do método — do mesmo
# jeito que `hydraulics.jl` está fora de `moran.jl`.
include("sizing/exchanger/bell_delaware.jl")
include("sizing/exchanger/shell_and_tube.jl")
include("memorial_specs/saari_lmtd.jl")

# O envoltório da Análise Pinch — e repare ONDE ele está: aqui embaixo, a ~140 linhas do
# `include("analysis/pinch.jl")` lá em cima. A distância é o ponto. O núcleo entra antes
# de `interfaces.jl` e não tem como citar `ParameterSpec`; este entra depois de tudo e
# cita à vontade. Juntar os dois arquivos apagaria a única garantia estrutural que o
# passo anterior deixou, e `test/pinch.jl` verifica que ela continua de pé.
include("analysis/pinch_method.jl")
include("memorial_specs/pinch_kemp.jl")

# Adaptador do módulo dinâmico: a ponte entre o TOML (SI) e a física isolada de
# `dynamics/`. Entra AQUI — depois de `config.jl`, `interfaces.jl` e do registro — porque
# é ele, e não a física, que cita `ParameterSpec` e lê a configuração. Ver `pinch_method.jl`.
include("dynamics/song_method.jl")

include("engine/single.jl")
include("engine/envelope.jl")

# --- interfaces e registro
export AbstractEquipment, AbstractSizingMethod, ParameterSpec
export method_id, label, parameters, applies_to, size_equipment
export parameter_groups, instance_key, group_instance, in_group, is_template, single_box
export register!, equipments, methods_for, equipment, sizing_method
export validate, defaults, with_defaults

# --- tipos
export PhaseProps, StreamState, stream_from_field, stream_from_case, field_units
export Interval, Case, CaseSet, expand, corner_count, active
export load_case_set, case_set_from_config, stream_parameters, stream_keys
export save_case_set, save_case_set_named, list_case_sets, case_set_path
export dir_casos, dirs_casos, nome_casos_valido
export BoxCatalogo, catalogo, box_catalogo, box_equipamento
export SizingResult, SweepRow, CalcTrace, TraceEntry, block_entries, vessel_volume
export EnvelopeResult, EnvelopeRow, trace_block_order

# --- o contrato genérico (src/engine/contract.jl)
export SweepAxis, ResultField, SweepColumn, column_value, der
export case_input, sweep_axis, requirement, governing_of, ceiling_of, derived
export admissible, case_admissible, objective, envelope_params, selection_message
export per_constraint, requirement_spec
export result_fields, sweep_columns, trace_blocks, governing_label, global_keys
export PhaseLayer, cross_section
export size_single, sweep_row, ceiling_mechanism_of, grid_hint, trace_selection!

# --- a camada documental (src/memorial.jl)
export MemorialSpec, PremissaDoc, EquacaoDoc, VariavelDoc, ResultadoDoc, VerificacaoDoc
export memorial_spec, tem_memorial, equacoes_do_rastro, equacoes_citadas
export entradas_do_rastro, SEM_EQUACAO, titulo_resultados, titulo_resumo

# --- vasos registrados
export AbstractVesselMethod, Separator, StewartArnold, VesselConstraints
export KnockoutDrum, StewartArnoldTwoPhase, gas_capacity_dleff
export sizing_constraints, method_config, method_reference, lss_from, size_vessel
export beta_coefficient, water_area_fraction, segment_height_fraction
export slenderness_equation, lss_trace

# --- os equipamentos que não são vasos
export CentrifugalPump, MoranPumpSizing, PumpConstraints
export reynolds_pipe, colebrook_white, darcy_friction, flow_regime, friction_equation
export straight_run_head, fittings_head, antoine_pressure
export ShellTubeExchanger, SaariLMTD, ExchangerDuty, ExchangerConstraints
export lmtd, f_correction_1_2, nusselt_dittus_boelter, overall_u
export effectiveness_ntu_counterflow
export ShellGeometry, bell_delaware, crossflow_area, shell_reynolds, colburn_ideal
export h_ideal, j_baffle_cut, j_leakage, j_bypass, j_spacing, j_laminar
export leakage_areas, baffle_clearance, layout_pitches
# O tratador NÃO exporta um tipo de restrições próprio nem função de campo elétrico:
# ele produz `VesselConstraints` como os outros vasos, e o campo elétrico entra pelo
# `dm_water` e por mais nada — ver a nota de limitação em `config/equipment/treater/`.
# Havia aqui `TreaterConstraints`, `dipole_force`, `coalescence_time` e
# `taylor_field_limit`, nenhum dos quatro definido em lugar nenhum: resto de um modelo
# de campo que a referência disponível não sustenta. Exportar nome que não existe
# promete uma API na saída de `names(FPSOSiz)` e entrega `UndefVarError` a quem a usar.
export ElectrostaticTreater, ArnoldElectrostatic
# A Análise Pinch registrada. `PinchTarget` NÃO é um equipamento — é o alvo da análise,
# e existe porque o contrato pede um `AbstractEquipment`. Ver `analysis/pinch_method.jl`.
export PinchTarget, PinchKemp, PinchConstraints
export converge_drag, terminal_velocity, reynolds, drag_coefficient, souders_brown
export size_envelope, governing_summary, mechanism_label

# --- o módulo dinâmico (Song 2023) e seu adaptador. A física vive nos submódulos
# `SongDynamics` e `Propriedades` (isolados); estas são as funções de fronteira.
export parametros_dinamico, valores_default_dinamico, config_dinamico
export construir_params_dinamico, estado_inicial_dinamico, simular_dinamico
export canais_dinamico, CanalSerie
export SeparadorDinamico, SongDinamico
export SongDynamics, Propriedades

"""
    stream_parameters() -> Vector{ParameterSpec}

Descritores das entradas de corrente (`config/stream.toml`), comuns a todos os
equipamentos.
"""
stream_parameters() = parameter_specs(load_config("stream.toml"))

"""
    default_case_values() -> Dict{Symbol,Float64}

Caso de referência completo: os defaults da corrente mais os do método de
Stewart & Arnold. Corresponde à Tabela 1 de Alves & Komesu (2025).
"""
function default_case_values()
    vals = defaults(stream_parameters())
    merge!(vals, defaults(parameters(StewartArnold())))
    return vals
end

function __init__()
    register!(Separator())
    register!(StewartArnold())
    register!(KnockoutDrum())
    register!(StewartArnoldTwoPhase())
    register!(ElectrostaticTreater())
    register!(ArnoldElectrostatic())
    register!(CentrifugalPump())
    register!(MoranPumpSizing())
    register!(ShellTubeExchanger())
    register!(SaariLMTD())
    register!(PinchTarget())
    register!(PinchKemp())
    # O separador dinâmico (Song 2023) — não é vaso e não dimensiona; registra-se para o
    # box do catálogo resolver e o formulário montar-se pelo ParameterSpec.
    register!(SeparadorDinamico())
    register!(SongDinamico())
    return nothing
end

end # module FPSOSiz
