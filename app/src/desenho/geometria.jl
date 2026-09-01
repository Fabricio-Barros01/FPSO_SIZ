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
    layer_heights(d_m, beta) -> (h_agua, h_oleo, nivel)

Alturas das camadas num vaso **trifásico** preenchido pela metade: `h_o = β·d`,
`h_w = (0,5 − β)·d`, e o nível de líquido em `d/2`. Ver `beta.jl` no core.

Só serve a três fases. Quem desenha usa [`camadas`](@ref), que também sabe responder
por um vaso de duas.
"""
function layer_heights(d_m, beta)
    h_oleo = beta * d_m
    nivel  = d_m / 2
    return (nivel - h_oleo, h_oleo, nivel)
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

"""
    camadas(d_m, beta) -> Vector{Camada}

As faixas de fase do vaso, de baixo para cima.

Com `beta` finito são **três** — água, óleo e gás, com `h_o = β·d` e `h_w = (0,5 − β)·d`.
Com `beta` igual a `NaN` são **duas**: água e líquido, porque um vaso bifásico não tem
interface líquido-líquido e β não existe nele (ver `VesselConstraints` no core, que usa
`NaN` para "não se aplica").

Esta função existe para que o desenho **pergunte quantas faixas há** em vez de deduzir
três de um número. Era essa dedução que fazia o vaso bifásico sair com `h_w = NaN·d` nas
coordenadas do SVG — e um SVG com `NaN` num atributo é descartado pelo navegador em
silêncio: a figura simplesmente não aparece, com status 200 e sem erro em lugar nenhum.
"""
function camadas(d_m, beta)
    nivel = d_m / 2
    gas = Camada("GÁS", nivel, d_m, Formato.GAS_ZONA, Formato.GAS_ZONA_OP,
                 Formato.TINTA_FRACA, Formato.TINTA_FRACA, "", false)

    isnan(beta) && return [
        Camada("LÍQUIDO", 0.0, nivel, Formato.OLEO_ZONA, Formato.OLEO_ZONA_OP,
               Formato.OLEO, "#ffffff", Formato.INTERNO, false),
        gas]

    hw, _, _ = layer_heights(d_m, beta)
    return [
        Camada("ÁGUA", 0.0, hw, Formato.AGUA_ZONA, Formato.AGUA_ZONA_OP,
               Formato.AGUA, "#ffffff", Formato.AGUA, true),
        Camada("ÓLEO", hw, nivel, Formato.OLEO_ZONA, Formato.OLEO_ZONA_OP,
               Formato.OLEO, "#ffffff", Formato.INTERNO, false),
        gas]
end

"""
    geometry_from(result, d_mm, beta) -> NamedTuple

Traduz um `EnvelopeResult` e um diâmetro selecionado na geometria que o desenho
consome. `ok = false` faz a cena inteira desenhar vazia, sem exceção.
"""
function geometry_from(res, d_mm::Real, beta::Real)
    (res === nothing || !res.feasible) &&
        return (; d_m = 0.0, leff_m = 0.0, lss_m = 0.0, beta = NaN,
                  camadas = Camada[], governing = :none, ok = false, sr = NaN)
    linha = argmin(r -> abs(r.d_mm - d_mm), res.rows)
    d_m = linha.d_mm / 1000
    return (; d_m, leff_m = linha.leff_m, lss_m = linha.lss_m, beta,
              camadas = camadas(d_m, beta), governing = linha.governing,
              ok = true, sr = linha.sr)
end
