"""
Tratador eletrostático horizontal, cheio de líquido — Stewart & Arnold (2008),
§4.7 a §4.9.6.

É o terceiro vaso do registro, e o primeiro que **não tem fase gasosa**: entra emulsão
óleo-água já desgaseificada e saem óleo tratado e água. Some o bloco de capacidade de
gás; sobram a decantação líquido-líquido e o tempo de retenção, nas formas
generalizadas de §4.9.4–4.9.6 (vaso com fração de líquido diferente de meio cheio), com
a fração valendo 1.

    Bloco B — decantação   (h_o)max = 0,033·(tr)o·ΔSG·d_m²/µ_o            Eq. 4.5b/§4.9.3
                           a_w      = α·Q_w(tr)w/(Q_o(tr)o + Q_w(tr)w)    Eq. 4.16
                           β_w      ← segmento circular de área a_w       Eq. 4.17
                           d_max    = (h_o)max/(β_l − β_w)                Eq. 4.18
    Bloco C — retenção     d²·L_eff = 21000·((tr)o·Q_o + (tr)w·Q_w)/α     Eq. 4.15b
    L_ss                   o maior entre L_eff + d/1000 e (4/3)·L_eff     §4.9.1
    Esbeltez               3 ≤ SR ≤ 5                                     §4.9.2

## O que o campo elétrico faz aqui, e o que ele não faz

Ele **coalesce**: o campo alinha os dipolos das gotículas de água dispersas no óleo e as
funde, e uma gotícula maior decanta com o quadrado do diâmetro (Stokes, Eq. 4.2b). É por
isso que um tratador eletrostático faz num vaso pequeno o que um decantador simples só
faria num vaso enorme — e é exatamente onde ele entra nas equações acima: no `d_m` do
bloco B, e em nenhum outro lugar.

**A referência não fecha o campo.** *Gas-Liquid and Liquid-Liquid Separators* — o volume
da série que este projeto tem — cita tratadores eletrostáticos quatro vezes, todas de
passagem, e remete o dimensionamento do campo (gradiente de tensão, espaçamento e área
de eletrodo, consumo do transformador) ao volume *Emulsions and Oil Treating*, que não
está em `References/`. Sem ele **não há correlação** que ligue tensão e espaçamento ao
diâmetro coalescido.

A escolha foi a única honesta disponível: `d_m` é **entrada do usuário**, com o valor
sem tratamento de §4.7.2 (500 µm) como constante de comparação, e o rastro de cálculo
emite o ganho de decantação `(d_m/500)²` que a hipótese vale. Assim o número que
carrega a premissa fica no memorial, ao lado do resultado que ele produziu, em vez de
escondido num default. Quem tiver dado de laboratório põe o dele; quem não tiver, lê no
memorial quanto está apostando.

O que o programa **não** faz, e não finge fazer: dimensionar o eletrodo, a fonte, ou
prever a coalescência a partir da tensão. Ver a nota de limitação no TOML.

## Três achados ao reproduzir a fonte

1. **O livro se contradiz num fator de 10.** A Eq. (4.5b) imprime
   `h_o = 0,0033·(tr)o·ΔSG·d_m²/µ`; o §4.9.3 passo 3, quatro páginas adiante, imprime
   `0,033` para a mesma equação. `0,033` é o certo: com `d_m = 500 µm` ele dá
   `8250·(tr)o·ΔSG/µ`, que é exatamente a Eq. (4.6b) do próprio livro, e fica a 1,5 % da
   conversão exata dos `320` da forma em unidades de campo (320 in × 25,4 = 8128 mm).
   Com `0,0033` daria 825 — dez vezes menos. O separador trifásico deste programa já
   usava `0,033` desde o Sprint 1, por Alves & Komesu; o livro confirma, e denuncia a
   própria errata.

2. **A Eq. (4.9b) tem erro de digitação.** Imprime `(h_w)max = 1520·(tr)w·ΔSG/µ_w` para
   `d_m = 200 µm`. A forma geral com `0,033` dá `0,033 × 200² = 1320`, e a conversão
   exata da Eq. (4.9a) de campo dá `51,2 in × 25,4 = 1300 mm` — 1,5 % de 1320 e 17 % de
   1520. O programa usa a forma geral, que é a que fecha com as outras três.

3. **§4.9.6 só dá o teto de água-em-óleo.** A Eq. (4.18) generaliza a Eq. (4.8) do vaso
   meio cheio, mas o livro não escreve a contraparte da Eq. (4.10) para o vaso cheio.
   Aqui ela é a geométrica — `d_max = (h_w)max/β_w`, a espessura de água dividida pela
   fração de altura que a água ocupa —, e ela **governa quando for menor**. É a leitura
   conservadora, e é diferente da decisão do separador trifásico, onde a forma publicada
   (não conservadora) foi mantida para reproduzir a Tabela 3 do artigo. Aqui não há
   tabela a reproduzir, então não há motivo para preferir uma forma que a geometria
   contradiz. Ver a nota 3 em `stewart_arnold.jl`, que documenta o caso oposto.
"""

struct ElectrostaticTreater <: AbstractEquipment end
method_id(::ElectrostaticTreater) = :treater
label(::ElectrostaticTreater) = "Tratador Eletrostático Horizontal"

struct ArnoldElectrostatic <: AbstractVesselMethod end
method_id(::ArnoldElectrostatic) = :arnold_electrostatic
applies_to(::ArnoldElectrostatic) = ElectrostaticTreater()

const _TRATADOR_CONFIG = ("equipment", "treater", "electrostatic.toml")

method_config(::ArnoldElectrostatic) = load_config(_TRATADOR_CONFIG...)
label(::ArnoldElectrostatic) =
    config_label(method_config(ArnoldElectrostatic()), "Stewart & Arnold (2008) — §4.9")
parameters(::ArnoldElectrostatic) =
    parameter_specs(method_config(ArnoldElectrostatic()))

"""
Seis entradas de corrente, não doze.

Sai tudo o que descreve o gás — vazão, densidade, viscosidade e o `Z` —, porque o vaso
é cheio de líquido: não há fase gasosa a separar, e portanto não há bloco A. Saem também
pressão e temperatura, que neste método não entram em conta nenhuma: as duas serviam à
Eq. 14 do bloco de gás, e sem ele pedi-las seria o defeito que `stream_keys` existe
para impedir.
"""
stream_keys(::ArnoldElectrostatic) =
    (:q_oil, :q_water, :rho_oil, :rho_water, :mu_oil, :mu_water)

"""
Chaves de corrente que este vaso reetiqueta **e** cujo default ele muda.

O rótulo, pelo mesmo motivo do vaso bifásico: "vazão de água" num tratador é a água
**residual** que veio emulsionada com o óleo, não uma corrente de água produzida.

O default, porque a diferença é de duas ordens de grandeza e ela decide se a tela abre
num vaso plausível ou num impossível. `config/stream.toml` traz 1025,8 m³/h porque foi
escrito para o separador trifásico, que é justamente o equipamento que **retira** essa
água. O tratador fica a jusante dele e recebe o que passou. Herdar 1025,8 aqui abriria a
aplicação num caso que não fecha — a fase aquosa ocupando a seção inteira — e a primeira
coisa que o usuário veria seria uma mensagem de inviabilidade sobre dados que ele não
digitou.

Só o default muda; unidade, faixa e ordem continuam vindo do arquivo compartilhado.
"""
const _AJUSTES_TRATADOR = Dict(
    :q_oil   => ("Vazão de óleo", 215.8,
                 "Óleo tratado que atravessa o vaso. Eq. 4.15b e Eq. 4.16."),
    :q_water => ("Vazão de água emulsionada", 25.0,
                 "Água que chega EMULSIONADA no óleo, não uma corrente de água livre — " *
                 "esta fica a jusante de um separador, que já retirou a água livre. " *
                 "Eq. 4.15b e Eq. 4.16."),
    :mu_oil  => ("Viscosidade do óleo", 10.0,
                 "Fase contínua da decantação da água (Eq. 4.5b). É a variável a que o " *
                 "tamanho do vaso é mais sensível depois do tempo de retenção."),
)

function stream_parameters(m::ArnoldElectrostatic)
    specs = filter(s -> s.key in stream_keys(m), stream_parameters())
    return map(specs) do s
        novo = get(_AJUSTES_TRATADOR, s.key, nothing)
        novo === nothing && return s
        return ParameterSpec(s.key, novo[1], s.unit, novo[2], s.min, s.max,
                             s.advanced, novo[3])
    end
end

"""
    sizing_constraints(m::ArnoldElectrostatic, s, p, k)

Blocos B e C. Sem bloco A: o vaso é cheio de líquido, e o `d·Leff` de capacidade de gás
entra como **zero** — que é o valor honesto (nenhuma exigência), e que faz
`governing_of` apontar sempre para o líquido sem nenhum caso especial no motor.
"""
function sizing_constraints(m::ArnoldElectrostatic, s::StreamState,
                            p::AbstractDict, k::AbstractDict)
    tr = CalcTrace()
    fu = field_units(s)

    alpha  = float(k[:liquid_area_fraction])
    c_set  = float(k[:settling_coefficient])
    c_ret  = float(k[:retention_coefficient])
    dm_ref = float(k[:untreated_droplet_um])

    dm_w, dm_o = p[:dm_water], p[:dm_oil]
    tr_o, tr_w = p[:tr_oil], p[:tr_water]

    # ---------------------------------------------------------------- bloco B
    dsg = fu.sg_w - fu.sg_o
    trace!(tr, :settling, "Eq. 4.16", "ΔSG", "(SG)w − (SG)o", dsg, "–")
    dsg > 0 || return (false,
        "Densidade do óleo ≥ densidade da água (ΔSG = $(round(dsg, digits = 4))): " *
        "não há separação gravitacional líquido-líquido, e o campo elétrico coalesce " *
        "mas não decanta.", tr)

    # O ganho que a coalescência eletrostática vale, em decantação: Stokes vai com d_m².
    # Não é correlação — é a hipótese do usuário tornada visível. Ver a nota no topo.
    ganho = (dm_w / dm_ref)^2
    trace!(tr, :settling, "Eq. 4.2b", "ganho do campo",
           "(d_m/$(round(Int, dm_ref)) µm)² — hipótese de coalescência, não correlação",
           ganho, "×")

    ho_max = c_set * tr_o * dsg * dm_w^2 / fu.mu_o
    hw_max = c_set * tr_w * dsg * dm_o^2 / fu.mu_w
    trace!(tr, :settling, "Eq. 4.5b", "(h_o)max", "0,033·(tr)o·ΔSG·d_m²/µ_o", ho_max, "mm")
    trace!(tr, :settling, "Eq. 4.9b", "(h_w)max", "0,033·(tr)w·ΔSG·d_m²/µ_w", hw_max, "mm")

    aw = alpha * fu.q_w * tr_w / (tr_o * fu.q_o + tr_w * fu.q_w)
    isfinite(aw) || return (false,
        "As vazões e os tempos de retenção não permitem repartir a seção entre óleo e " *
        "água (Eq. 4.16): confira se ao menos uma das duas vazões é positiva.", tr)

    beta_w = segment_height_fraction(aw)
    beta_l = segment_height_fraction(alpha)
    trace!(tr, :settling, "Eq. 4.16", "a_w", "α·Qw(tr)w/((tr)oQo + (tr)wQw)", aw, "–")
    trace!(tr, :settling, "Eq. 4.17", "β_w", "altura do segmento de área a_w", beta_w, "–")

    beta_o = beta_l - beta_w
    beta_o > 0 || return (false,
        "A fase aquosa ocupa toda a seção do vaso (a_w = $(round(aw, digits = 4))): " *
        "não sobra altura para a camada de óleo, e o bloco de decantação não tem onde " *
        "acontecer.", tr)

    d_max_wio = ho_max / beta_o
    d_max_oiw = hw_max / beta_w
    trace!(tr, :settling, "Eq. 4.18", "d_max (água em óleo)", "(h_o)max/(β_l − β_w)",
           d_max_wio, "mm")
    # Sem água emulsionada (a_w = 0), `β_w = 0` e `d_max_oiw = Inf` — que perde no mínimo
    # abaixo e não decide nada. A linha é só documental, então é omitida em vez de sujar
    # o memorial assinado com `Inf` (mesmo defeito e mesma decisão do separador, D.1).
    beta_w > 0 && trace!(tr, :settling, "Eq. 4.18*", "d_max (óleo em água)",
           "(h_w)max/β_w — contraparte geométrica; ver a nota 3 em electrostatic.jl",
           d_max_oiw, "mm")

    d_max, mechanism = d_max_wio <= d_max_oiw ? (d_max_wio, :water_in_oil) :
                                                (d_max_oiw, :oil_in_water)

    # ---------------------------------------------------------------- bloco C
    d2_leff = c_ret * (tr_o * fu.q_o + tr_w * fu.q_w) / alpha
    trace!(tr, :liquid, "Eq. 4.15b", "d²·Leff", "21000·((tr)oQo + (tr)wQw)/α",
           d2_leff, "mm²·m")
    isfinite(d2_leff) && d2_leff > 0 || return (false,
        "Vazões não informadas ou inválidas: a capacidade de líquido (Eq. 4.15b) não " *
        "pôde ser avaliada.", tr)

    # `d_leff_gas = 0`: sem fase gasosa não há exigência de comprimento por arraste. Não
    # é `NaN` — é zero mesmo, e a diferença importa: `NaN` contaminaria o `max` do motor.
    return (true, VesselConstraints(0.0, d2_leff, d_max, mechanism, beta_o, aw), tr)
end

"""
    lss_from(::ArnoldElectrostatic, d_mm, leff, gov, k)

O **maior** entre `Leff + d/1000` e `(4/3)·Leff`, como manda §4.9.1 — a mesma regra do
vaso bifásico, e pelo mesmo motivo: são duas folgas construtivas independentes e o vaso
tem de atender às duas. Aqui a fonte é o livro, então segue-se o livro; o separador
trifásico segue o artigo, que simplifica. Ver a nota 4 em `stewart_arnold.jl`.
"""
lss_from(::ArnoldElectrostatic, d_mm::Real, leff::Real, gov::Symbol,
         k::AbstractDict) =
    max(leff + d_mm / 1000.0, float(k[:lss_liquid_factor]) * leff)

slenderness_equation(::ArnoldElectrostatic) = "§4.9.2"

# Como no bifásico, UMA citação para a regra inteira: §4.9.1 manda tomar o maior entre as
# duas folgas, e citar só a que venceu diria que a outra não foi avaliada.
lss_trace(::ArnoldElectrostatic, gov::Symbol) =
    ("§4.9.1", "max(Leff + d/1000 ; (4/3)·Leff)")

"""
    per_constraint(m::ArnoldElectrostatic, d, c)

Só o bloco de líquido. O default da família dos vasos devolve também `:gas`, que aqui
seria uma curva constante em zero no gráfico e uma coluna de zeros no memorial —
prometendo um bloco que este vaso não tem.
"""
per_constraint(::ArnoldElectrostatic, d_mm::Real, c::VesselConstraints) =
    Dict{Symbol,Float64}(:liquid => c.d2_leff / d_mm^2)

"""
    cross_section(m::ArnoldElectrostatic, c)

**Duas** faixas, e nenhuma delas é gás: α = 1, o vaso é cheio de líquido.

O default da família dos vasos devolve `[água 0,5 − β, óleo β, gás 0,5]`, que é a
geometria do vaso **meio cheio** — e aqui `β` é a altura do óleo dentro de um vaso
cheio, que passa de 0,5 com facilidade (0,896 com os defaults deste TOML). Herdar aquele
default dava uma camada de água de altura `0,5 − 0,896 = −0,396·d` — negativa — e uma
metade de gás num equipamento que não tem fase gasosa. Era a mesma classe de defeito que
`cross_section` foi escrita para acabar, sobrevivendo por falta de uma linha.

`β_w = 1 − β_o` porque as duas fases repartem a seção inteira: é a Eq. (4.17) com a
fração líquida valendo 1.
"""
cross_section(::ArnoldElectrostatic, c::VesselConstraints) =
    [PhaseLayer(:water, 1.0 - c.beta), PhaseLayer(:oil, c.beta)]

"""
    trace_blocks(m::ArnoldElectrostatic)

Sem "Bloco A": o vaso não tem fase gasosa. O memorial já pularia o bloco vazio, mas
declará-lo aqui seria prometer no índice o que não existe no texto.
"""
trace_blocks(::ArnoldElectrostatic) = [
    :settling  => "Bloco B — decantação líquido-líquido",
    :liquid    => "Bloco C — capacidade de líquido",
    :selection => "Seleção do diâmetro",
]

governing_label(::ArnoldElectrostatic, g::Symbol) =
    g === :liquid ? "capacidade de líquido (retenção)" :
    g === :gas    ? "capacidade de gás" : String(g)

size_equipment(eq::ElectrostaticTreater, m::ArnoldElectrostatic, s::StreamState,
               params::AbstractDict) = size_vessel(eq, m, s, params)
