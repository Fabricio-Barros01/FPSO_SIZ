"""
Primitivas de SVG.

O desenho e os gráficos são strings montadas aqui — nenhuma biblioteca gráfica. Duas
consequências práticas: o bundle do PackageCompiler não carrega rasterizador nenhum, e
o mesmo código que a tela mostra é o que vai para o arquivo em `saida/`, então figura e
números não têm como divergir.

## Coordenadas

O mundo é em metros com **y crescendo para cima** (como no `Axis` do Makie); o SVG tem
**y crescendo para baixo**. A conversão é explícita, ponto a ponto, em [`para`](@ref) —
e não por um `transform="scale(1,-1)"` no grupo, que espelharia todo o texto junto.
"""

# ---------------------------------------------------------------------------
# Escape
# ---------------------------------------------------------------------------

"""
    escapa(s) -> String

Escapa texto para dentro de XML. Necessário de verdade: nomes de caso vêm do TOML do
usuário e do expansor de cantos (`"Faixa de operação [q_oil↑ q_water↓]"`), e vão parar
tanto no `<text>` do SVG quanto no HTML.
"""
function escapa(s)
    t = string(s)
    t = replace(t, '&' => "&amp;")
    t = replace(t, '<' => "&lt;")
    t = replace(t, '>' => "&gt;")
    t = replace(t, '"' => "&quot;")
    return replace(t, '\'' => "&#39;")
end

# ---------------------------------------------------------------------------
# Tela: a transformação mundo → pixel
# ---------------------------------------------------------------------------

"""
Retângulo do mundo mapeado no retângulo do SVG.

`escx` e `escy` separados permitem os dois usos: o desenho do vaso quer escala igual
nos dois eixos (o `DataAspect()` do Makie), os gráficos querem escalas independentes.
"""
struct Tela
    x0::Float64; y0::Float64      # canto inferior-esquerdo, no mundo
    escx::Float64; escy::Float64  # px por unidade de mundo
    esq::Float64; topo::Float64   # deslocamento em px (margem)
    larg::Float64; alt::Float64   # tamanho total do SVG, em px
end

"""
    tela_proporcional(x0, y0, x1, y1; larg, margem) -> Tela

Escala igual nos dois eixos: o vaso na tela tem a proporção do vaso real. A altura do
SVG sai da geometria, não é escolhida.
"""
function tela_proporcional(x0, y0, x1, y1; larg = 900.0, margem = 6.0)
    dx = max(x1 - x0, 1e-9)
    dy = max(y1 - y0, 1e-9)
    esc = (larg - 2margem) / dx
    return Tela(x0, y0, esc, esc, margem, margem, larg, dy * esc + 2margem)
end

"""
    tela_livre(x0, y0, x1, y1; larg, alt, margem) -> Tela

Escalas independentes, para os gráficos: `d` em milímetros no eixo x e `Leff` em metros
no y não têm proporção comum.
"""
function tela_livre(x0, y0, x1, y1; larg, alt, margem)
    dx = max(x1 - x0, 1e-9)
    dy = max(y1 - y0, 1e-9)
    return Tela(x0, y0,
                (larg - margem.esq - margem.dir) / dx,
                (alt - margem.topo - margem.base) / dy,
                margem.esq, margem.topo, larg, alt)
end

"Converte um ponto do mundo para pixel de SVG. É aqui que o eixo y se inverte."
function para(t::Tela, p)
    x, y = p[1], p[2]
    px = t.esq + (x - t.x0) * t.escx
    py = t.alt - t.topo - (y - t.y0) * t.escy
    return (px, py)
end

"Só o x, em pixel."
parax(t::Tela, x) = t.esq + (x - t.x0) * t.escx

"Só o y, em pixel."
paray(t::Tela, y) = t.alt - t.topo - (y - t.y0) * t.escy

# ---------------------------------------------------------------------------
# Elementos
# ---------------------------------------------------------------------------

"""
    svgn(x) -> String

Número para dentro de um atributo de SVG. Três milésimos bastam em coordenada de
pixel, e o ponto decimal é obrigatório: o SVG não lê a vírgula que o resto do programa
usa. Não-finito vira `0` — assim uma geometria degenerada produz figura torta em vez
de um documento inválido que o navegador recusa inteiro.
"""
svgn(x::Real) = isfinite(x) ? rstrip(rstrip(string(round(float(x); digits = 3)), '0'), '.') : "0"

"Monta a lista `attr=\"valor\"`, pulando o que vier como `nothing`."
function atrs(pares...)
    partes = String[]
    for (k, v) in pares
        v === nothing && continue
        push!(partes, string(k, "=\"", v isa Real ? svgn(v) : escapa(v), "\""))
    end
    return join(partes, " ")
end

"Lista `points=\"x,y x,y …\"` já convertida para pixel."
pontos(t::Tela, pts) = join([string(svgn(p[1]), ",", svgn(p[2])) for p in (para(t, q) for q in pts)], " ")

"""
    poligono(t, pts; preenche, opacidade, traco, largura) -> String

Área fechada. Lista vazia devolve string vazia — é assim que um estado inviável
"desenha nada" sem `if` espalhado pelos chamadores.
"""
function poligono(t::Tela, pts; preenche = "none", opacidade = nothing,
                  traco = nothing, largura = nothing)
    isempty(pts) && return ""
    return string("<polygon ", atrs("points" => pontos(t, pts), "fill" => preenche,
                                    "fill-opacity" => opacidade, "stroke" => traco,
                                    "stroke-width" => largura), "/>")
end

"Linha aberta por uma lista de pontos."
function polilinha(t::Tela, pts; traco = "#000", largura = 1.0, estilo = nothing,
                   preenche = "none", opacidade = nothing, junta = "round")
    isempty(pts) && return ""
    return string("<polyline ", atrs("points" => pontos(t, pts), "fill" => preenche,
                                     "stroke" => traco, "stroke-width" => largura,
                                     "stroke-dasharray" => estilo,
                                     "stroke-opacity" => opacidade,
                                     "stroke-linejoin" => junta), "/>")
end

"Segmento entre dois pontos do mundo."
function segmento(t::Tela, p1, p2; traco = "#000", largura = 1.0, estilo = nothing,
                  opacidade = nothing)
    a, b = para(t, p1), para(t, p2)
    return string("<line ", atrs("x1" => a[1], "y1" => a[2], "x2" => b[1], "y2" => b[2],
                                 "stroke" => traco, "stroke-width" => largura,
                                 "stroke-dasharray" => estilo,
                                 "stroke-opacity" => opacidade), "/>")
end

"Retângulo dado em pixel — para faixas de fundo e molduras, que não vivem no mundo."
function caixa_px(x, y, w, h; preenche = "none", opacidade = nothing, traco = nothing,
                  largura = nothing, raio = nothing)
    return string("<rect ", atrs("x" => x, "y" => y, "width" => max(w, 0.0),
                                 "height" => max(h, 0.0), "fill" => preenche,
                                 "fill-opacity" => opacidade, "stroke" => traco,
                                 "stroke-width" => largura, "rx" => raio), "/>")
end

"Círculo num ponto do mundo, com raio em pixel."
function marcador(t::Tela, p; raio = 5.0, preenche = "#000", traco = nothing,
                  largura = nothing)
    c = para(t, p)
    return string("<circle ", atrs("cx" => c[1], "cy" => c[2], "r" => raio,
                                   "fill" => preenche, "stroke" => traco,
                                   "stroke-width" => largura), "/>")
end

"""
    texto(t, p, s; ...) -> String

Rótulo ancorado num ponto do mundo. `ancora` é `"start" | "middle" | "end"`, `base` é
`"auto" | "middle" | "hanging"`. `giro` em graus, aplicado em torno do próprio ponto —
é o que põe a cota do diâmetro na vertical sem espelhar as letras.
"""
function texto(t::Tela, p, s; tam = 11, cor = "#000", ancora = "middle",
               base = "middle", peso = nothing, giro = nothing, dx = 0.0, dy = 0.0)
    isempty(string(s)) && return ""
    x, y = para(t, p)
    x += dx; y += dy
    transf = giro === nothing ? nothing : string("rotate(", svgn(giro), " ", svgn(x), " ", svgn(y), ")")
    return string("<text ", atrs("x" => x, "y" => y, "font-size" => tam, "fill" => cor,
                                 "text-anchor" => ancora, "dominant-baseline" => base,
                                 "font-weight" => peso, "transform" => transf),
                  ">", escapa(s), "</text>")
end

"Texto posicionado direto em pixel — eixos e legendas, que não pertencem ao mundo."
function texto_px(x, y, s; tam = 11, cor = "#000", ancora = "middle", base = "middle",
                  peso = nothing)
    isempty(string(s)) && return ""
    return string("<text ", atrs("x" => x, "y" => y, "font-size" => tam, "fill" => cor,
                                 "text-anchor" => ancora, "dominant-baseline" => base,
                                 "font-weight" => peso), ">", escapa(s), "</text>")
end

"""
    recorte(id, x, y, w, h) -> String

Define uma região de corte. `id` tem de ser único **no documento HTML inteiro**, não só
neste SVG: a página injeta vários SVGs no mesmo DOM e `url(#id)` repetido resolve
sempre para o primeiro. Por isso o identificador vem do chamador, e não de um contador.
"""
recorte(id::AbstractString, x, y, w, h) =
    string("<clipPath ", atrs("id" => id), ">",
           caixa_px(x, y, w, h), "</clipPath>")

"Agrupa elementos sob um recorte declarado por [`recorte`](@ref)."
recortado(id::AbstractString, corpo) =
    string("<g clip-path=\"url(#", escapa(id), ")\">", corpo, "</g>")

"""
    espalhar(ys, minimo) -> Vector{Float64}

Afasta rótulos que ficariam colados, preservando a ordem. Necessário de verdade: numa
corrente rica em água β é pequeno, a camada de óleo tem centímetros, e as cotas `hₒ` e
`nível` cairiam uma sobre a outra no corte.

Passa uma vez para baixo empurrando o que estiver perto demais e outra para cima
corrigindo quem foi parar fora do quadro — é o suficiente para meia dúzia de rótulos.
"""
function espalhar(ys::AbstractVector{<:Real}, minimo::Real)
    out = collect(float.(ys))
    ordem = sortperm(out)
    for (a, b) in zip(ordem, Iterators.drop(ordem, 1))
        out[b] - out[a] < minimo && (out[b] = out[a] + minimo)
    end
    return out
end

"""
    documento(t, corpo; fundo, rotulo) -> String

Envelopa os elementos num `<svg>` com `viewBox`, para que a figura escale sozinha
dentro do `<div>` que a contém. `preserveAspectRatio` mantém a proporção; sem ele o
vaso deformaria junto com a janela.

`rotulo` vazio NÃO vira `aria-label=""`: `atrs` só pula o que vier como `nothing`, e um
`role="img"` com nome vazio é pior que nenhum dos dois — o leitor de tela anuncia
"gráfico sem nome" *e* deixa de ler os `<text>` de dentro, que é onde estava a mensagem.
Sem rótulo, a figura sai sem `role` nenhum e o conteúdo volta a ser alcançável.
"""
function documento(t::Tela, corpo::AbstractString; fundo = nothing, rotulo = "")
    fundinho = fundo === nothing ? "" :
               caixa_px(0, 0, t.larg, t.alt; preenche = fundo)
    tem_rotulo = !isempty(strip(string(rotulo)))
    return string(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ",
        svgn(t.larg), " ", svgn(t.alt), "\" ",
        atrs("preserveAspectRatio" => "xMidYMid meet",
             "role" => tem_rotulo ? "img" : nothing,
             "aria-label" => tem_rotulo ? rotulo : nothing),
        " font-family=\"system-ui, -apple-system, Segoe UI, Roboto, sans-serif\">",
        fundinho, corpo, "</svg>")
end

"""
SVG vazio, do tamanho pedido — o que um estado inviável devolve.

A mensagem vai também no rótulo, e não só desenhada: é justamente no estado inviável que
a figura não tem nada a mostrar, e o `<text>` do meio é a única explicação na tela. Sem o
rótulo, quem usa leitor de tela ficava sem nenhuma — o desenho some e nada o substitui.
"""
function documento_vazio(larg, alt, mensagem = "")
    t = Tela(0.0, 0.0, 1.0, 1.0, 0.0, 0.0, float(larg), float(alt))
    corpo = isempty(mensagem) ? "" :
            texto_px(larg / 2, alt / 2, mensagem; tam = 12, cor = "#6b717a")
    return documento(t, corpo; rotulo = mensagem)
end
