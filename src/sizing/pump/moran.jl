"""
Bomba centrífuga: carga do sistema, NPSH disponível e potência — Moran, *Pump Sizing:
Bridging the Gap Between Theory and Practice*, CEP dez/2016.

O primeiro equipamento do programa que **não é um vaso**, e por isso a primeira prova
real do que o Sprint 7 fez: não há aqui varredura, escolha de ponto, motor de envelope
nem uma linha de interface. O arquivo declara o que uma linha de recalque é, e devolve
a carga que ela exige em cada diâmetro.

## O que se varre, e por quê

Uma bomba não tem diâmetro de casco nem esbeltez. O que se escolhe numa especificação
de bomba em fase conceitual é o **diâmetro da tubulação**, e é dele que sai tudo o mais:

    v(DN)  = Q/A                       velocidade superficial
    Re(DN) = ρvD/µ                     regime
    f(DN)  = Colebrook-White           fator de Darcy
    H(DN)  = h_est + h_reta + h_local  carga do sistema
    →  a bomba é especificada por (Q, H) no ponto de operação

`H` é o que o motor envelopa: dois casos de operação exigem cargas diferentes no mesmo
DN, e a bomba tem de atender ao maior. É exatamente o mesmo movimento do `Leff` de um
vaso, com outra grandeza — que é o que o contrato de `src/engine/contract.jl` existe
para permitir.

## A banda tem dois lados, e um deles não cabia no motor

A faixa de velocidade que o artigo recomenda (p. 39) tem os dois lados, e os dois são
dele: `< 1,5 m/s` para "pumped water-like fluids", e `> 1, < 1,5 m/s` para "water-like
fluids with settleable solids" — que é o caso de uma linha de água produzida, e é de onde
vem o piso. Para líquido limpo o artigo só impõe o teto; `v_min = 0` no formulário
recupera essa regra, e o `note` do TOML o diz. Os dois lados amarram o DN em sentidos
opostos:

    v ≤ v_max  ⟹  DN ≥ DN_min      (linha estreita demais eroderia)
    v ≥ v_min  ⟹  DN ≤ DN_max      (linha larga demais deixaria decantar)

e **os dois dependem da vazão, que é de cada caso**. O `ceiling_of` do motor só sabia
expressar o segundo, e `admissible` só enxerga o caso governante — o de maior carga, que
não é necessariamente o de maior vazão. Com dois casos, o de vazão alta podia estourar
`v_max` sem que nada olhasse. Daí [`case_admissible`](@ref), acrescentado ao contrato
neste sprint: o motor o avalia para **todos** os casos, e é onde a banda inteira e a
margem de NPSH deste método moram.

## O que a fonte não dá, e o que se fez

1. **As equações são imagem no PDF.** Recuperadas da prosa e conferidas contra os dois
   números publicados — ver `hydraulics.jl`, que também explica por que Zigrang-Sylvester
   e Haaland ficaram de fora.
2. **Não há regime laminar.** Ver [`darcy_friction`](@ref).
3. **Diâmetro nominal × diâmetro interno.** O artigo trata os dois como o mesmo número:
   o texto lê a Figura 3 para "a 25-mm nominal-bore pipe" num eixo rotulado *Internal
   Diameter, mm*. O programa faz o mesmo, e o declara: numa fase conceitual a diferença
   entre DN e diâmetro interno de um Sch 40 é da ordem de 5 %, e o passo da série
   comercial é maior que isso. Quem precisar do interno real põe o número na grade — a
   grade é dado, não código.
4. **Não há critério econômico.** O artigo dá regras de bolso de velocidade, não um
   ótimo de custo. O programa escolhe o **menor DN admissível**, que é a escolha de
   menor capital na fase conceitual; e é uma escolha discutível, porque diâmetro menor é
   mais carga e mais energia por toda a vida da bomba. Ela fica visível: a tabela de
   varredura mostra `H` e a potência em cada DN da banda, então o desvio para o DN
   seguinte custa um clique e é lido em kW.
"""

struct CentrifugalPump <: AbstractEquipment end
method_id(::CentrifugalPump) = :pump
label(::CentrifugalPump) = "Bomba Centrífuga e Linha de Recalque"

struct MoranPumpSizing <: AbstractSizingMethod end
method_id(::MoranPumpSizing) = :moran
applies_to(::MoranPumpSizing) = CentrifugalPump()

const _MORAN_CONFIG = ("equipment", "pump", "moran.toml")

method_config(::MoranPumpSizing) = load_config(_MORAN_CONFIG...)
label(::MoranPumpSizing) = config_label(method_config(MoranPumpSizing()),
                                        "Moran (2016) — carga do sistema")
parameters(::MoranPumpSizing) = parameter_specs(method_config(MoranPumpSizing()))

"""
Cinco entradas de corrente, não doze.

A bomba move **uma** fase líquida: sai tudo o que descreve gás e fase aquosa, e sai o
`Z`, que é compressibilidade de gás. Ficam vazão, densidade, viscosidade, temperatura
(que a Antoine consome) e pressão — aqui a do **reservatório de sucção**, que é o que
entra no NPSH disponível.

A fase líquida ocupa a posição do óleo em [`StreamState`](@ref), como no vaso bifásico,
e os rótulos são reescritos abaixo para dizer o que ela de fato é.
"""
stream_keys(::MoranPumpSizing) = (:q_oil, :rho_oil, :mu_oil, :pressure, :temperature)

"""
Chaves da corrente que esta tela renomeia **e** cujo default ela muda.

O rótulo, porque a bomba move um líquido só e chamá-lo de óleo pediria ao usuário um
dado que ele pode não reconhecer como o seu.

O default, para que a aplicação abra **coerente consigo mesma**. Dois casos, e os dois
importam:

* `pressure` em `config/stream.toml` vale 2300 kPa, que é a pressão de operação do
  separador trifásico para que o arquivo foi escrito. Aqui o campo é a pressão do
  **reservatório de sucção**, e 2300 kPa na sucção contra os 400 kPa de recalque do
  default dá carga estática de **−218 m**: o líquido escoaria sozinho, e a tela abriria
  mostrando uma bomba de carga negativa. Vale 101,3 kPa — tanque aberto.
* o líquido default passa a ser **água a 30 °C**, e não o óleo da Tabela 1. É a única
  escolha coerente com os coeficientes de Antoine default, que são os da água (Tabela 3
  do artigo, o único número que a fonte publica). Densidade de óleo com Antoine de água
  daria uma pressão de vapor que não é de nenhum dos dois, e o NPSH sairia errado sem
  que nada denunciasse. Trocou o líquido, troque A, B e C junto.
"""
const _AJUSTES_BOMBA = Dict(
    :q_oil    => ("Vazão bombeada", 60.0,
                  "Vazão no ponto de operação. Entra em v = Q/A e na potência."),
    :rho_oil  => ("Densidade do líquido", 998.0,
                  "Entra no Reynolds, na carga estática por pressão e na potência. " *
                  "O default é água a 30 °C, coerente com a Antoine default."),
    :mu_oil   => ("Viscosidade do líquido", 1.0,
                  "Entra no Reynolds, e por ele no fator de atrito de Darcy. " *
                  "1,0 cP é água a ~20 °C; 0,8 a 30 °C."),
    :pressure => ("Pressão no reservatório de sucção", 101.3,
                  "Absoluta. É o P₀ do NPSH disponível, e a parcela de sucção da carga " *
                  "estática. 101,3 kPa = tanque aberto à atmosfera."),
    :temperature => ("Temperatura", 30.0,
                  "Entra na equação de Antoine, que dá a pressão de vapor do NPSH. " *
                  "30 °C é a linha que a Tabela 3 do artigo publica resolvida."),
)

function stream_parameters(m::MoranPumpSizing)
    specs = filter(s -> s.key in stream_keys(m), stream_parameters())
    return map(specs) do s
        novo = get(_AJUSTES_BOMBA, s.key, nothing)
        novo === nothing && return s
        return ParameterSpec(s.key, novo[1], s.unit, novo[2], s.min, s.max,
                             s.advanced, novo[3])
    end
end

"""
As restrições de uma linha que **não** dependem do diâmetro.

Tudo o que depende de DN — velocidade, Reynolds, atrito, NPSH disponível — é recalculado
por [`_hidraulica`](@ref) em cada ponto da varredura, porque é justamente a variação
dessas grandezas com o diâmetro que a varredura existe para mostrar.
"""
struct PumpConstraints
    q_m3s::Float64        # vazão, m³/s
    q_m3h::Float64        # a mesma, na unidade da potência
    rho::Float64          # kg/m³
    mu::Float64           # Pa·s
    h_est::Float64        # carga estática total (cota + pressões), m
    npsh_estatico::Float64 # (P₀ − Pv)/(ρg) + h₀, m — antes de descontar o atrito
    npsh_exigido::Float64  # NPSH requerido + margem, m
    l_suc::Float64
    k_suc::Float64
    l_rec::Float64
    k_rec::Float64
    rugosidade_m::Float64
    rendimento::Float64
    g::Float64
    k::Dict{Symbol,Any}   # constantes do TOML, para o laço de Colebrook-White
end

"""
    sizing_constraints(m::MoranPumpSizing, s, p, k)

Monta a [`PumpConstraints`](@ref): carga estática, NPSH estático e o que a linha tem de
fixo. Nada aqui depende do diâmetro.

A carga estática é `Δz + (P_rec − P_suc)/(ρg)` — o artigo a descreve como "criada por
qualquer coluna vertical de líquido ligada à bomba e por qualquer sistema pressurizado
ligado à saída", e diz que ela **existe com a bomba desligada e não varia com a vazão**.
As duas parcelas são exatamente isso.
"""
function sizing_constraints(m::MoranPumpSizing, s::StreamState,
                            p::AbstractDict, k::AbstractDict)
    tr = CalcTrace()
    fu = field_units(s)
    g  = float(k[:gravity])

    rho, mu, q_h = fu.rho_o, s.oil.viscosity, fu.q_o
    (isfinite(rho) && rho > 0) || return (false,
        "Densidade do líquido não informada ou inválida: sem ela não há carga " *
        "estática por pressão nem Reynolds.", tr)
    (isfinite(mu) && mu > 0) || return (false,
        "Viscosidade do líquido não informada ou inválida: o fator de atrito de " *
        "Darcy não pôde ser avaliado.", tr)
    (isfinite(q_h) && q_h > 0) || return (false,
        "Vazão bombeada não informada ou inválida.", tr)

    # ------------------------------------------------------------ carga estática
    p_suc = Units.kpa_to_pa(fu.p_kpa)
    p_rec = Units.kpa_to_pa(p[:p_recalque])
    h_pressao = (p_rec - p_suc) / (rho * g)
    h_est = p[:h_geometrica] + h_pressao

    trace!(tr, :estatica, "—", "Δz", "cota de recalque − cota de sucção",
           p[:h_geometrica], "m")
    trace!(tr, :estatica, "—", "h_pressão", "(P_rec − P_suc)/(ρg)", h_pressao, "m")
    trace!(tr, :estatica, "—", "h_est", "Δz + h_pressão", h_est, "m")

    # ------------------------------------------------------------------- NPSH
    pv = antoine_pressure(p[:antoine_a], p[:antoine_b], p[:antoine_c], fu.t_k)
    isfinite(pv) || return (false,
        "A equação de Antoine não pôde ser avaliada (confira A, B, C e a " *
        "temperatura): sem pressão de vapor não há NPSH disponível.", tr)
    npsh_est = (p_suc - pv) / (rho * g) + p[:h_sucao]

    trace!(tr, :npsh, "Antoine", "Pv", "10^(A − B/(T+C)) bar", pv, "Pa")
    trace!(tr, :npsh, "—", "NPSH sem atrito", "(P₀ − Pv)/(ρg) + h₀", npsh_est, "m")
    trace!(tr, :npsh, "—", "NPSH exigido", "NPSHr + margem",
           p[:npsh_requerido] + p[:npsh_margem], "m")

    cons = PumpConstraints(
        Units.m3h_to_m3s(q_h), q_h, rho, mu, h_est, npsh_est,
        p[:npsh_requerido] + p[:npsh_margem],
        p[:l_sucao], p[:k_sucao], p[:l_recalque], p[:k_recalque],
        Units.mm_to_m(p[:rugosidade]), p[:rendimento], g, Dict{Symbol,Any}(k))
    return (true, cons, tr)
end

"""
    _hidraulica(c, dn_mm) -> NamedTuple

Tudo o que depende do diâmetro, num ponto só: velocidade, Reynolds, fator de atrito e
regime, as duas perdas de carga e o NPSH disponível.

Uma função e não quatro porque as quatro compartilham o `v` e o `f`, e porque
[`requirement`](@ref), [`derived`](@ref) e [`case_admissible`](@ref) precisam das mesmas
grandezas no mesmo ponto — separá-las faria o laço de Colebrook-White rodar três vezes
por ponto de grade sem nenhum ganho de clareza.
"""
function _hidraulica(c::PumpConstraints, dn_mm::Real)
    d = Units.mm_to_m(dn_mm)
    d > 0 || return (; d, v = Inf, re = NaN, f = NaN, regime = :indefinido,
                     confiavel = false, hf_suc = Inf, hf_rec = Inf, h_atrito = Inf,
                     h_total = Inf, npsh = -Inf)

    v  = c.q_m3s / (π * d^2 / 4)
    re = reynolds_pipe(c.rho, v, d, c.mu)
    f, regime, confiavel = darcy_friction(re, c.rugosidade_m / d, c.k)

    hf_suc = straight_run_head(f, c.l_suc, d, v, c.g) + fittings_head(c.k_suc, v, c.g)
    hf_rec = straight_run_head(f, c.l_rec, d, v, c.g) + fittings_head(c.k_rec, v, c.g)

    return (; d, v, re, f, regime, confiavel, hf_suc, hf_rec,
            h_atrito = hf_suc + hf_rec, h_total = c.h_est + hf_suc + hf_rec,
            npsh = c.npsh_estatico - hf_suc)
end

# ---------------------------------------------------------------------------
# O contrato de engine/contract.jl
# ---------------------------------------------------------------------------

"A série de diâmetros da Figura 3, recortada pela faixa que o usuário pediu."
function sweep_axis(m::MoranPumpSizing, p::AbstractDict)
    serie = Float64.(constants(method_config(m))[:nominal_diameters])
    return SweepAxis(:dn, "diâmetro nominal", "mm",
                     filter(d -> p[:dn_min] <= d <= p[:dn_max], serie))
end

global_keys(::MoranPumpSizing) = [:dn_min, :dn_max, :v_min, :v_max]

requirement(::MoranPumpSizing, dn::Real, c::PumpConstraints) = _hidraulica(c, dn).h_total

"Qual parcela domina a carga naquele diâmetro — o que o cartão e o CSV mostram."
governing_of(::MoranPumpSizing, dn::Real, c::PumpConstraints) =
    _hidraulica(c, dn).h_atrito > c.h_est ? :atrito : :estatica

per_constraint(::MoranPumpSizing, dn::Real, c::PumpConstraints) =
    Dict{Symbol,Float64}(:estatica => c.h_est, :atrito => _hidraulica(c, dn).h_atrito)

"""
    derived(m::MoranPumpSizing, dn, h, gov, c, k, p)

O que a tela mostra além do par (DN, H): velocidade, Reynolds, fator de atrito, as
parcelas da carga, o NPSH disponível, a folga de NPSH e a potência de eixo.

A potência usa a vazão do **caso governante** e a carga da envelope. É a leitura
conservadora e não é a única possível: com casos de vazões muito diferentes, o de maior
vazão pode pedir mais potência a uma carga menor. O rastro do caso único de cada corrente
mostra a potência dela isolada — é onde essa diferença fica visível.

`:confiavel` sai como `0.0`/`1.0` porque o dicionário é de `Float64`, e sai **junto** com
a fronteira que o julgou (`:re_min_correlacao`): um flag sem o número contra o qual ele
foi decidido obriga quem lê o CSV a ir buscar a fronteira no TOML. Os dois são o que faz
[`selection_message`](@ref) poder distinguir "fora da faixa da correlação" de "fora da
banda de velocidade" — que pedem ações opostas ao usuário.
"""
function derived(m::MoranPumpSizing, dn::Real, h::Real, gov::Symbol,
                 c::PumpConstraints, k::AbstractDict, p::AbstractDict)
    hid = _hidraulica(c, dn)
    return Dict{Symbol,Float64}(
        :v        => hid.v,
        :re       => hid.re,
        :f        => hid.f,
        :h_est    => c.h_est,
        :h_atrito => hid.h_atrito,
        :npsh     => hid.npsh,
        :folga_npsh => hid.npsh - c.npsh_exigido,
        :confiavel  => hid.confiavel ? 1.0 : 0.0,
        :re_min_correlacao => float(k[:reynolds_turbulent_min]),
        :re_max_laminar    => float(k[:reynolds_laminar_max]),
        :potencia => Units.hydraulic_power_kw(c.rho, c.q_m3h, h, c.rendimento; g = c.g))
end

"""
    case_admissible(m::MoranPumpSizing, dn, c, p)

A banda de velocidade, a margem de NPSH e a **faixa de validade da correlação de
atrito**, deste caso.

As condições dependem da vazão, que é do caso, e por isso não podem viver em
[`admissible`](@ref), que só enxerga o caso governante. Ver a nota no topo do arquivo.

# Por que a faixa da correlação recusa o ponto

A Eq. (2) do artigo (p. 41) é declarada para `Re > 4.000`, e é a única correlação de
atrito turbulento que este método implementa. Entre `Re` 2.300 e 4.000 não há correlação
nenhuma que valha — a zona é instável por natureza, e o próprio TOML o diz. Colebrook-
White avaliada ali devolve número como qualquer outro, e o número não avisa.

Um ponto fora do domínio de validade não é necessariamente impossível: é um ponto que o
modelo implementado **não está autorizado a avaliar**. Aceitá-lo seria escolher um
diâmetro a partir de uma perda de carga que nenhuma equação desta implementação sustenta
— e a escolha sai com a mesma aparência de todas as outras. Daí a recusa, com o motivo
dito em [`selection_message`](@ref).

O regime **laminar** passa: `f = 64/Re` é exata para escoamento plenamente desenvolvido
em duto circular, e `flow_regime` já a marca `confiavel = true`. A recusa é da zona de
transição e da não-convergência, não de "fora de Colebrook-White" — as duas coisas são
diferentes, e confundi-las recusaria todo óleo pesado sem motivo.
"""
function case_admissible(::MoranPumpSizing, dn::Real, c::PumpConstraints,
                         p::AbstractDict)
    hid = _hidraulica(c, dn)
    return p[:v_min] <= hid.v <= p[:v_max] && hid.npsh >= c.npsh_exigido &&
           hid.confiavel
end

# Não há critério de conjunto: velocidade e NPSH são de cada caso e já foram checados em
# `case_admissible`. Declarado explicitamente, e não deixado ao acaso de um default, para
# que a ausência seja uma afirmação e não um esquecimento.
admissible(::MoranPumpSizing, dn::Real, der::AbstractDict, p::AbstractDict) = true

"""
    objective(m::MoranPumpSizing, dn, der, p)

O **menor** DN admissível. Ver a nota 4 no topo do arquivo: é a escolha de menor
capital, não um ótimo de custo de ciclo de vida — o artigo não oferece um.
"""
objective(::MoranPumpSizing, dn::Real, der::AbstractDict, p::AbstractDict) = dn

"""
    envelope_params(m::MoranPumpSizing, params)

Grade união, banda interseção — a mesma assimetria dos vasos, e pelo mesmo motivo: a
grade é onde se **procura** e a banda é o que se **aceita**. A linha é uma só.
"""
function envelope_params(::MoranPumpSizing, params::Vector{<:AbstractDict})
    v_min = maximum(p[:v_min] for p in params)
    v_max = minimum(p[:v_max] for p in params)
    v_min <= v_max || return (false,
        "As bandas de velocidade pedidas pelos casos não se cruzam: um exige " *
        "v ≥ $(v_min) m/s e outro v ≤ $(v_max) m/s. Como a linha é uma só, não há " *
        "velocidade que atenda a todos.")
    return (true, Dict{Symbol,Float64}(
        :dn_min => minimum(p[:dn_min] for p in params),
        :dn_max => maximum(p[:dn_max] for p in params),
        :v_min  => v_min,
        :v_max  => v_max))
end

"""
    selection_message(m::MoranPumpSizing, rows, teto, p)

Por que nenhum DN serviu — e qual das **quatro** condições o recusou.

Distinguir importa porque as ações são opostas: "amplie a grade de DN" resolve a banda de
velocidade, "eleve o nível do reservatório de sucção" resolve cavitação, e "reveja a
viscosidade ou a temperatura" é a única que tira a linha da zona de transição. Dar o
diagnóstico errado manda o usuário mexer no que não é o problema.

A ordem das perguntas é a ordem em que uma condição torna a seguinte irrelevante: fora da
banda de velocidade não faz sentido discutir a faixa da correlação, e fora da faixa da
correlação não faz sentido discutir o NPSH — o `hf` que entra no NPSH é justamente o que
não vale ali.
"""
function selection_message(m::MoranPumpSizing, rows, teto::Real, p::AbstractDict;
                           mechanism::Symbol = :none)
    isempty(rows) && return "A grade de diâmetros nominais ficou vazia."
    vs = [get(r.derivados, :v, NaN) for r in rows]
    folgas = [get(r.derivados, :folga_npsh, NaN) for r in rows]
    na_banda = findall(v -> p[:v_min] <= v <= p[:v_max], vs)

    if isempty(na_banda)
        lo, hi = extrema(filter(isfinite, vs))
        return "Nenhum diâmetro da grade mantém a velocidade na banda " *
               "$(p[:v_min])–$(p[:v_max]) m/s: na grade oferecida ela varia de " *
               "$(round(lo, digits = 2)) a $(round(hi, digits = 2)) m/s. Amplie a " *
               "grade de DN, ou reveja a banda."
    end

    # Fora da faixa em que a fonte declara a correlação de atrito. Vem ANTES do NPSH
    # porque o NPSH desconta `hf_suc`, que é justamente a perda que não vale ali:
    # acusar cavitação com base nela seria diagnosticar a partir do número recusado.
    validos = filter(i -> get(rows[i].derivados, :confiavel, 1.0) != 0.0, na_banda)
    if isempty(validos)
        res = [get(rows[i].derivados, :re, NaN) for i in na_banda]
        re_lo, re_hi = extrema(filter(isfinite, res))
        lam = get(rows[first(na_banda)].derivados, :re_max_laminar, 2300.0)
        turb = get(rows[first(na_banda)].derivados, :re_min_correlacao, 4000.0)
        return "Na banda de velocidade $(p[:v_min])–$(p[:v_max]) m/s todos os " *
               "diâmetros caem na zona de transição do escoamento (Re de " *
               "$(round(re_lo, digits = 0)) a $(round(re_hi, digits = 0)), entre " *
               "$(round(lam, digits = 0)) e $(round(turb, digits = 0))), onde nenhuma " *
               "correlação de atrito desta implementação vale: o artigo declara " *
               "Colebrook-White para Re > $(round(turb, digits = 0)) e f = 64/Re " *
               "só até Re $(round(lam, digits = 0)). O programa não extrapola. " *
               "Reveja a viscosidade ou a temperatura do líquido, ou mude a banda de " *
               "velocidade para deslocar o Reynolds."
    end

    # A maior folga entre os DN que a velocidade admite E cuja correlação vale. Se ela é
    # negativa, todos cavitam e a causa é essa; se é positiva, a recusa veio de outro
    # caso — e quem sabe disso é o motor, que acrescenta a frase da interseção vazia.
    # Afirmar cavitação aqui sem conferir o sinal foi um defeito real: a primeira versão
    # deste texto acusava cavitação com folga de +26 m.
    melhor = maximum(folgas[i] for i in validos)
    if !(isfinite(melhor) && melhor < 0)
        return "Há diâmetros na banda de velocidade $(p[:v_min])–$(p[:v_max]) m/s, e " *
               "neles o NPSH tem folga (a maior é $(round(melhor, digits = 2)) m). " *
               "A recusa não veio deste caso."
    end
    return "Na banda de velocidade $(p[:v_min])–$(p[:v_max]) m/s todos os diâmetros " *
           "cavitam: a maior folga de NPSH é $(round(melhor, digits = 2)) m, e ela " *
           "precisa ser ≥ 0. Suba o nível do reservatório de sucção, encurte a linha " *
           "de sucção, reduza a temperatura, ou escolha bomba de menor NPSH requerido."
end

governing_label(::MoranPumpSizing, g::Symbol) =
    g === :atrito   ? "perda por atrito" :
    g === :estatica ? "carga estática" : String(g)

requirement_spec(::MoranPumpSizing) = ("carga do sistema", "m")

"""
    result_fields(m::MoranPumpSizing, r)

O cartão da bomba. Dois campos carregam sinal: a velocidade (que é a banda) e a folga de
NPSH (que é a cavitação). São as duas coisas que reprovam um diâmetro, e o cartão segue
o cursor — arrastá-lo para fora da banda tem de acender ✗ em uma das duas.
"""
function result_fields(m::MoranPumpSizing, r)
    tem = r.feasible && isfinite(r.x)
    txt(v) = tem ? v : "—"
    ok = !tem ? :neutro : (hasproperty(r, :ok) ? r.ok : true) ? :ok : :erro
    folga = der(r, :folga_npsh)
    st_npsh = !tem || !isfinite(folga) ? :neutro : folga >= 0 ? :ok : :erro
    return ResultField[
        ResultField("Diâmetro nominal DN", tem ? r.x : NaN; unit = "mm", digits = 0,
                    highlight = true),
        ResultField("Carga do sistema H", tem ? r.y : NaN; unit = "m", highlight = true),
        ResultField("Velocidade v", der(r, :v); unit = "m/s", status = ok),
        ResultField("Carga estática", der(r, :h_est); unit = "m"),
        ResultField("Perda de carga", der(r, :h_atrito); unit = "m"),
        ResultField("Reynolds", der(r, :re); digits = 0),
        ResultField("Fator de atrito f", der(r, :f); digits = 4),
        ResultField("NPSH disponível", der(r, :npsh); unit = "m"),
        ResultField("Folga de NPSH", folga; unit = "m", status = st_npsh),
        ResultField("Potência de eixo", der(r, :potencia); unit = "kW"),
        ResultField("Parcela governante", txt(governing_label(m, r.governing))),
        ResultField("Caso governante", txt(_driver_case(r))),
    ]
end

sweep_columns(::MoranPumpSizing) = [
    SweepColumn("DN (mm)",   :x; digits = 0),
    SweepColumn("H (m)",     :y),
    SweepColumn("v (m/s)",   :v),
    SweepColumn("NPSHd (m)", :npsh),
    SweepColumn("P (kW)",    :potencia),
]

trace_blocks(::MoranPumpSizing) = [
    :estatica  => "Bloco A — carga estática",
    :npsh      => "Bloco B — NPSH disponível",
    :selection => "Seleção do diâmetro nominal",
]

grid_hint(::MoranPumpSizing, p::AbstractDict) =
    "A grade é a série da Figura 3 recortada por DN mínimo ($(p[:dn_min])) e " *
    "DN máximo ($(p[:dn_max]))."

"""
    trace_selection!(m::MoranPumpSizing, tr, best, p)

Carimba no memorial o que só existe **no diâmetro escolhido**: velocidade, Reynolds,
regime, fator de atrito, as duas perdas e a potência.

Este bloco é o que torna o memorial da bomba conferível à mão, e é a única via por onde
o regime de escoamento chega ao leitor — Colebrook-White fora da faixa em que o artigo a
declara (`Re > 4000`) devolve número como qualquer outro, e o número não avisa.

**Duas linhas saem daqui e não de uma constante:** o `regime`, e a equação citada ao lado
do `f`. A citação vem de [`friction_equation`](@ref), que despacha no regime — carimbar
"Colebrook" sobre um `f` que veio de `64/Re` manda o leitor conferir a conta na equação
errada, e era o que este bloco fazia até a fase de validação física. Ver
`docs/validacao/01-bomba-moran.md`, defeito 2.
"""
function trace_selection!(m::MoranPumpSizing, tr::CalcTrace, best, p::AbstractDict)
    d = best.derivados
    re = get(d, :re, NaN)
    k  = constants(method_config(m))
    regime, confiavel = flow_regime(re, k)
    fonte_f, forma_f = friction_equation(regime)

    trace!(tr, :selection, "—", "DN escolhido",
           "menor DN com $(p[:v_min]) ≤ v ≤ $(p[:v_max]) m/s, NPSH folgado e " *
           "correlação de atrito válida",
           best.x, "mm")
    trace!(tr, :selection, "—", "v", "Q/(πD²/4)", get(d, :v, NaN), "m/s")
    trace!(tr, :selection, "—", "Re", "ρvD/µ", re, "–")
    # O regime como GRANDEZA do memorial, e não como adjetivo numa frase: é ele que diz
    # qual das duas relações de atrito vale, e é a única linha do bloco cujo valor não é
    # um número. `1`/`0` em "válida?" é o mesmo 0/1 que `derived` expõe no CSV.
    trace!(tr, :selection, "§ regime", "regime",
           "laminar até Re $(round(float(k[:reynolds_laminar_max]), digits = 0)); " *
           "turbulento a partir de $(round(float(k[:reynolds_turbulent_min]), digits = 0)) " *
           "— aqui: $(regime)",
           confiavel ? 1.0 : 0.0, "válida?")
    trace!(tr, :selection, fonte_f, "f", forma_f, get(d, :f, NaN), "–")
    trace!(tr, :selection, "Darcy", "h_atrito", "f·(L/D)·v²/2g + Σk·v²/2g",
           get(d, :h_atrito, NaN), "m")
    trace!(tr, :selection, "—", "H", "h_est + h_atrito", best.y, "m")
    trace!(tr, :selection, "—", "NPSH disponível", "(P₀−Pv)/(ρg) + h₀ − h_atrito,suc",
           get(d, :npsh, NaN), "m")
    trace!(tr, :selection, "—", "P", "ρgQH/(3,6×10⁶·η)", get(d, :potencia, NaN), "kW")
    return nothing
end

size_equipment(eq::CentrifugalPump, m::MoranPumpSizing, s::StreamState,
               params::AbstractDict) = size_single(eq, m, s, params)
