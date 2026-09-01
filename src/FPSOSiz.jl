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

include("interfaces.jl")
include("registry.jl")

include("types/results.jl")
include("types/stream.jl")
include("types/cases.jl")

# depois dos tipos: o carregador de casos constrói `Case`
include("config.jl")

# O contrato método ↔ motor de envelope, antes de qualquer método que o implemente.
include("sizing/constraints.jl")

include("sizing/separator/beta.jl")
include("sizing/separator/drag.jl")
# Bloco de capacidade de gás: idêntico nos dois vasos, então mora fora de ambos.
include("sizing/gas_capacity.jl")
include("sizing/separator/stewart_arnold.jl")
include("sizing/knockout/two_phase.jl")

include("engine/envelope.jl")

# --- interfaces e registro
export AbstractEquipment, AbstractSizingMethod, ParameterSpec
export method_id, label, parameters, applies_to, size_equipment
export register!, equipments, methods_for, equipment, sizing_method
export validate, defaults, with_defaults

# --- tipos
export PhaseProps, StreamState, stream_from_field, stream_from_case, field_units
export Interval, Case, CaseSet, expand, corner_count, active
export load_case_set, case_set_from_config, stream_parameters, stream_keys
export save_case_set, save_case_set_named, list_case_sets, case_set_path
export dir_casos, dirs_casos, nome_casos_valido
export SizingResult, SweepRow, CalcTrace, TraceEntry, block_entries, vessel_volume
export EnvelopeResult, EnvelopeRow

# --- vasos registrados
export Separator, StewartArnold, VesselConstraints
export KnockoutDrum, StewartArnoldTwoPhase, gas_capacity_dleff
export sizing_constraints, method_config, method_reference, lss_from, size_vessel
export beta_coefficient, water_area_fraction
export converge_drag, terminal_velocity, reynolds, drag_coefficient, souders_brown
export size_envelope, governing_summary, mechanism_label

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
    return nothing
end

end # module FPSOSiz
