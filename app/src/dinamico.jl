"""
Tela dinâmica (Song 2023) — a ponte app ↔ simulador.

Isolada como o resto do subapp: **não passa pelo `AppState` nem pelo fluxo de
dimensionamento**. A física corre em `FPSOSiz.simular_dinamico`; aqui só se monta o dado
da página (os campos do formulário) e se agrupa a trajetória devolvida em painéis de
série temporal, com um resumo do regime. Nenhuma grandeza é citada pelo nome no código da
interface: os campos vêm do `ParameterSpec` e os painéis, dos canais declarados.
"""

const _SD = FPSOSiz.SongDynamics

"""
    dados_dinamico(box) -> Dict

Dados injetados na página dinâmica. Os campos do formulário vêm do `ParameterSpec`, e vão
sob a chave `esquema` (com `equipamento`) para caber no MESMO contrato que o teste de
fumaça cobra de todo box ativo (`smoke.jl`: `d.esquema.campos`, `d.esquema.equipamento`).
"""
function dados_dinamico(box::FPSOSiz.BoxCatalogo)
    campos = [Dict("key" => String(s.key), "label" => s.label, "unit" => s.unit,
                   "default" => s.default, "min" => s.min, "max" => s.max,
                   "advanced" => s.advanced, "note" => s.note)
              for s in FPSOSiz.parametros_dinamico()]
    eq = FPSOSiz.box_equipamento(box)[1]
    return Dict("box" => box.id, "titulo" => box.titulo,
                "esquema" => Dict("campos" => campos,
                                  "equipamento" => FPSOSiz.label(eq)))
end

"""
    valores_do_corpo(corpo) -> Dict{Symbol,Float64}

Extrai o dicionário de valores do corpo JSON, só o que é numérico e finito. Chave
desconhecida é ignorada por `with_defaults` lá adiante; valor não numérico é descartado
aqui para a física nunca receber `NaN` de um campo em branco.
"""
function valores_do_corpo(corpo::AbstractDict)
    bruto = get(corpo, "valores", Dict{String,Any}())
    out = Dict{Symbol,Float64}()
    bruto isa AbstractDict || return out
    for (k, v) in bruto
        n = v isa Real ? float(v) : Formato.parse_num(string(v))
        n === nothing && continue
        isfinite(n) && (out[Symbol(k)] = n)
    end
    return out
end

# Tolerâncias de regime permanente (A.7), na unidade de EXIBIÇÃO de cada variável:
# pressão em kPa, níveis em m, abertura adimensional, φ fração.
const _EPS_REGIME = (pressao = 0.10, nivel = 0.0002, abertura = 0.001, fracao = 1e-4)

_regime(v, janela, dt_reg, eps) =
    _SD.regime_permanente(collect(Float64, v), float(janela), float(dt_reg), float(eps))

"Uma série para [`svg_serie_temporal`](@ref): nome, valores e cor."
_serie(nome, ys, cor) = (nome = nome, ys = collect(Float64, ys), cor = cor)

"""
    resultado_dinamico(r, valores; malha_fechada) -> Dict

Traduz o resultado da simulação para o que a tela consome: os painéis de série temporal
já em SVG (agrupados por eixo), um resumo do estado final e do regime, e a barra de
status. Inviabilidade (CFL) volta como `ok = false` com a mensagem — nunca exceção.
"""
function resultado_dinamico(r, valores::AbstractDict; malha_fechada::Bool)
    if r isa _SD.Inviabilidade
        return Dict{String,Any}("ok" => false, "graficos" => String[],
            "resumo" => Dict{String,Any}(),
            "status" => r.mensagem, "status_ok" => false)
    end

    p = FPSOSiz.with_defaults(FPSOSiz.parametros_dinamico(), valores)
    janela = p[:janela_regime]
    dt_reg = p[:cadencia_registro]

    t = r.t
    P_kpa = r.P ./ 1000
    qo_h = r.q_oleo .* 3600
    qw_h = r.q_agua .* 3600
    qg_h = r.q_gas .* 3600

    graficos = String[
        svg_serie_temporal(t, [_serie("Pressão", P_kpa, Formato.DESTAQUE)];
                           titulo = "Pressão", ylabel = "kPa"),
        svg_serie_temporal(t, [_serie("Água", r.H_agua, Formato.AGUA),
                               _serie("Óleo", r.H_oleo, Formato.OLEO)];
                           titulo = "Níveis", ylabel = "m"),
        svg_serie_temporal(t, [_serie("Óleo", r.ab_oleo, Formato.OLEO),
                               _serie("Água", r.ab_agua, Formato.AGUA),
                               _serie("Gás", r.ab_gas, Formato.TINTA_FRACA)];
                           titulo = "Aberturas das válvulas", ylabel = "fração"),
        svg_serie_temporal(t, [_serie("Esquerda", r.phi_esq, Formato.OLEO),
                               _serie("Direita", r.phi_dir, Formato.DESTAQUE)];
                           titulo = "Água no óleo (φ)", ylabel = "fração"),
        svg_serie_temporal(t, [_serie("Saída óleo", qo_h, Formato.OLEO),
                               _serie("Saída água", qw_h, Formato.AGUA),
                               _serie("Saída gás", qg_h, Formato.TINTA_FRACA)];
                           titulo = "Vazões de saída", ylabel = "m³/h"),
    ]

    fim = length(t)
    reg = Dict{String,Bool}(
        "pressao" => _regime(P_kpa, janela, dt_reg, _EPS_REGIME.pressao),
        "agua"    => _regime(r.H_agua, janela, dt_reg, _EPS_REGIME.nivel),
        "oleo"    => _regime(r.H_oleo, janela, dt_reg, _EPS_REGIME.nivel),
        "phi"     => _regime(r.phi_esq, janela, dt_reg, _EPS_REGIME.fracao))
    todos = all(values(reg))

    resumo = Dict{String,Any}(
        "horizonte"   => t[fim],
        "pressao_kpa" => P_kpa[fim],
        "sp_pressao"  => p[:sp_pressao],
        "h_agua"      => r.H_agua[fim],
        "h_oleo"      => r.H_oleo[fim],
        "ab_oleo"     => r.ab_oleo[fim],
        "ab_agua"     => r.ab_agua[fim],
        "ab_gas"      => r.ab_gas[fim],
        "phi_esq"     => r.phi_esq[fim],
        "phi_dir"     => r.phi_dir[fim],
        "folga_cfl"   => minimum(r.folga_cfl),
        "malha"       => malha_fechada ? "fechada" : "aberta",
        "regime"      => reg,
        "regime_todos" => todos,
        "carimbos"    => r.carimbos)

    modo = malha_fechada ? "malhas fechadas" : "malha aberta (§3.1)"
    sat = r.ab_gas[fim] >= 0.999 ? " — válvula de gás saturada em 100 %" : ""
    status = "Simulação (" * modo * "): $(round(Int, t[fim])) s, pressão " *
             "$(Formato.num(P_kpa[fim], 1)) kPa" * sat *
             ", φ (esq.) $(Formato.num(r.phi_esq[fim], 3))." *
             (todos ? " Regime permanente atingido." : " Ainda em transitório.") *
             (isempty(r.carimbos) ? "" :
              " Correlação fora de faixa: " * join(r.carimbos, "; ") * ".")

    return Dict{String,Any}("ok" => true, "graficos" => graficos,
        "resumo" => resumo, "status" => status, "status_ok" => true)
end
