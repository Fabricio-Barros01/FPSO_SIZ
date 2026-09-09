"""
Geometria do vaso, em metros.

Estas funções vinham de `views/vessel_draw.jl` na versão Makie e mudaram numa única
coisa: `Point2f` virou [`Pt`](@ref), uma tupla comum. Com isso o arquivo deixou de ter
dependência nenhuma — é aritmética pura, que serve igualmente ao SVG da tela e ao SVG
gravado em `saida/`.

Tudo em **coordenadas reais**: o vaso na tela tem a proporção do vaso real. Mover o
cursor de diâmetro engorda e encurta o desenho porque a geometria vem do mesmo
`EnvelopeResult` que alimenta os números da coluna de resultados; não há nenhuma
constante de desenho "ajustada no olho".

A seção transversal é o que torna as Eq. 18–19 visíveis: mostra `Aw/A` como área e a
altura fracionária β como cota, que é exatamente o que a Figura 3 relaciona.
"""

"Um ponto no plano, em metros. Substitui o `Point2f` do Makie."
const Pt = NTuple{2,Float64}

"Profundidade do tampo elíptico 2:1, em m."
head_depth(d_m) = d_m / 4

"""
    hull_profile(d_m, lss_m, y) -> (x_esq, x_dir)

Extensão horizontal do casco na altura `y` (medida do fundo). Casco cilíndrico de
`0` a `lss`, com tampos elípticos 2:1 nas duas pontas.
"""
function hull_profile(d_m, lss_m, y)
    R = d_m / 2
    t = (y - R) / R                       # −1 no fundo, +1 no topo
    ext = head_depth(d_m) * sqrt(max(1 - t^2, 0.0))
    return (-ext, lss_m + ext)
end

"""
    hull_band(d_m, lss_m, y1, y2; n) -> Vector{Pt}

Polígono de uma faixa horizontal do vaso, do nível `y1` ao `y2`, acompanhando os
tampos. Usado tanto para as zonas de fase quanto para o contorno completo.
"""
function hull_band(d_m, lss_m, y1, y2; n::Int = 40)
    pts = Pt[]
    ys = range(y1, y2; length = n)
    for y in ys
        push!(pts, (hull_profile(d_m, lss_m, y)[1], y))
    end
    for y in Iterators.reverse(ys)
        push!(pts, (hull_profile(d_m, lss_m, y)[2], y))
    end
    return pts
end

"Polígono de uma faixa horizontal da seção circular, de `y1` a `y2` (medidos do fundo)."
function circle_band(d_m, y1, y2; n::Int = 60)
    R = d_m / 2
    pts = Pt[]
    ys = range(y1, y2; length = n)
    halfw(y) = sqrt(max(R^2 - (y - R)^2, 0.0))
    for y in ys
        push!(pts, (-halfw(y), y))
    end
    for y in Iterators.reverse(ys)
        push!(pts, (halfw(y), y))
    end
    return pts
end

"""
Uma faixa de fase dentro do vaso, do fundo (`y0`) ao topo (`y1`), em metros.

`interface` é a cor da linha que fecha a faixa **por cima**; vazia quando não há linha
a desenhar (o topo da fase gasosa é o próprio casco). `cor` é a da linha e da cota, que
precisa de contraste sobre o papel; `zona` é a do preenchimento; `rotulo` a do texto
escrito dentro da faixa.
"""
struct Camada
    nome::String
    y0::Float64
    y1::Float64
    zona::String
    opacidade::Float64
    cor::String
    rotulo::String
    interface::String
    tracejada::Bool
end

altura(c::Camada) = c.y1 - c.y0
meio(c::Camada)   = (c.y0 + c.y1) / 2

"Aparência de cada fase: preenchimento, opacidade, cor da cota e cor do rótulo interno."
const _TINTA_FASE = Dict(
    :water => (Formato.AGUA_ZONA, Formato.AGUA_ZONA_OP, Formato.AGUA,        "#ffffff"),
    :oil   => (Formato.OLEO_ZONA, Formato.OLEO_ZONA_OP, Formato.OLEO,        "#ffffff"),
    :gas   => (Formato.GAS_ZONA,  Formato.GAS_ZONA_OP,  Formato.TINTA_FRACA, Formato.TINTA_FRACA),
)

"Cor da linha que fecha a faixa por cima, e se ela é tracejada."
const _INTERFACE_FASE = Dict(
    :water => (Formato.AGUA, true),      # tracejada: é interface líquido-líquido
    :oil   => (Formato.INTERNO, false),  # o nível de líquido
    :gas   => ("", false),
)

"""
    camadas(d_m, layers::Vector{PhaseLayer}) -> Vector{Camada}

As faixas de fase do vaso, de baixo para cima, a partir do que o **método** declarou em
`cross_section`.

O desenho não deduz mais nada: recebe as frações de altura já repartidas e só as
empilha. A versão anterior recebia `β` e deduzia três faixas dele (`h_w = (0,5 − β)·d`,
gás na metade de cima), o que é a geometria de um vaso **meio cheio** — correta para o
separador trifásico e para o knockout, e errada para o tratador eletrostático, que é
cheio de líquido. Lá `β` passa de 0,5 (0,896 com os defaults) e a dedução dava camada de
água com altura **negativa** mais uma faixa de gás num vaso sem fase gasosa.

Duas regras de rotulagem, que são do desenho e não do modelo:

* fase líquida única chama-se **LÍQUIDO**, e não "ÓLEO": num knockout de linha de gás o
  líquido é condensado, e o desenho não deve batizá-lo de óleo;
* a faixa **de cima não recebe linha de interface** — o topo dela é o próprio casco.
"""
function camadas(d_m, layers::Vector{FPSOSiz.PhaseLayer})
    isempty(layers) && return Camada[]

    # "LÍQUIDO" quando não há uma segunda fase líquida da qual distinguir o óleo.
    tem_agua = any(l -> l.fase === :water, layers)
    nome(f) = f === :water ? "ÁGUA" :
              f === :gas   ? "GÁS"  :
              tem_agua     ? "ÓLEO" : "LÍQUIDO"

    out = Camada[]
    y = 0.0
    for (i, l) in enumerate(layers)
        zona, op, cor, rotulo = get(_TINTA_FASE, l.fase,
                                    (Formato.GAS_ZONA, Formato.GAS_ZONA_OP,
                                     Formato.TINTA_FRACA, Formato.TINTA_FRACA))
        traco, tracejada = get(_INTERFACE_FASE, l.fase, ("", false))
        i == length(layers) && (traco = "")          # a de cima fecha no casco
        y1 = y + l.fracao * d_m
        push!(out, Camada(nome(l.fase), y, y1, zona, op, cor, rotulo, traco, tracejada))
        y = y1
    end
    return out
end

"Altura do topo da fase líquida mais alta, em m — o nível. `d_m` num vaso cheio."
nivel_liquido(g) =
    isempty(g.camadas) ? g.d_m / 2 :
    (i = findlast(c -> c.nome != "GÁS", g.camadas);
     i === nothing ? 0.0 : g.camadas[i].y1)

"Há fase gasosa neste vaso? O que só existe no céu de gás pergunta antes de se desenhar."
tem_gas(g) = any(c -> c.nome == "GÁS", g.camadas)

"""
    geometry_from(result, d_mm, layers, beta) -> NamedTuple

Traduz um `EnvelopeResult` e um diâmetro selecionado na geometria que o desenho
consome. `ok = false` faz a cena inteira desenhar vazia, sem exceção.

É aqui que os nomes genéricos do motor (`x`, `y`, `derivados`) voltam a ser diâmetro,
`Leff` e `Lss` — e é o lugar certo para isso: este arquivo desenha um vaso e sabe que
está desenhando um vaso. O que não podia acontecer era o **motor** saber.

`layers` é a geometria (de `cross_section`); `beta` é só a **cota** que o corte escreve,
e vale `NaN` onde o modelo não tem uma. São dois papéis, e misturá-los foi o defeito que
esta assinatura desfaz: quem desenha as faixas usa `layers`, quem anota usa `beta`.
"""
function geometry_from(res, d_mm::Real, layers::Vector{FPSOSiz.PhaseLayer},
                       beta::Real = NaN)
    (res === nothing || !res.feasible) &&
        return (; d_m = 0.0, leff_m = 0.0, lss_m = 0.0, beta = NaN,
                  camadas = Camada[], governing = :none, ok = false, sr = NaN)
    linha = argmin(r -> abs(r.x - d_mm), res.rows)
    d_m = linha.x / 1000
    return (; d_m, leff_m = linha.y, lss_m = FPSOSiz.der(linha, :lss), beta,
              camadas = camadas(d_m, layers), governing = linha.governing,
              ok = true, sr = FPSOSiz.der(linha, :sr))
end
