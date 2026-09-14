"""
Os dois gráficos da faixa inferior, em SVG.

**O gráfico de envelope** comunica o diferencial do software numa imagem só: uma curva
fina por caso e a envelope em negrito por cima de todas. Quem olha entende imediatamente
que o equipamento foi dimensionado para o pior caso em cada ponto do eixo, e não para
uma média.

**O gráfico de banda** mostra a faixa recomendada sombreada e onde o ponto escolhido
caiu dentro dela.

Nenhum dos dois cita `d`, `Leff` ou `SR`: título, rótulos de eixo e a chave do derivado
que se plota chegam por argumento, de quem sabe o que está dimensionando. Eram
`svg_grafico_leff` e `svg_grafico_sr`, com os nomes das grandezas do vaso no corpo — o
que fazia deles dois gráficos de separador em vez de dois gráficos.

Porte de `views/charts.jl`. O que o Makie dava de graça — eixos, grade, marcas — está
em [`moldura!`](@ref) e [`ticks_bonitos`](@ref) aqui embaixo.
"""

"Margens do painel de plotagem, em pixel."
const MARGEM_GRAFICO = (esq = 62.0, dir = 14.0, topo = 34.0, base = 44.0)

"""
    ticks_bonitos(lo, hi; alvo) -> Vector{Float64}

Marcas em múltiplos de 1, 2 ou 5 vezes uma potência de dez — o mesmo critério que
qualquer biblioteca de plotagem usa, escrito aqui para não trazer uma dependência
inteira por causa de cinco números.
"""
function ticks_bonitos(lo, hi; alvo::Int = 5)
    (isfinite(lo) && isfinite(hi) && hi > lo) || return Float64[]
    bruto = (hi - lo) / max(alvo, 1)
    mag = 10.0^floor(log10(bruto))
    norm = bruto / mag
    passo = (norm < 1.5 ? 1.0 : norm < 3.0 ? 2.0 : norm < 7.0 ? 5.0 : 10.0) * mag
    return collect(ceil(lo / passo) * passo:passo:hi)
end

"""
    moldura!(p, t, xs, ys; ...) -> p

Painel, grade, eixos e rótulos. Devolve as mesmas peças para todos os gráficos, para
que os dois tenham a mesma leitura.
"""
function moldura!(p, t::Tela, xs, ys; titulo = "", xlabel = "", ylabel = "",
                  fx = string, fy = string)
    x_esq, x_dir = MARGEM_GRAFICO.esq, t.larg - MARGEM_GRAFICO.dir
    y_topo, y_base = MARGEM_GRAFICO.topo, t.alt - MARGEM_GRAFICO.base

    push!(p, caixa_px(x_esq, y_topo, x_dir - x_esq, y_base - y_topo;
                      preenche = Formato.PAINEL))

    for x in xs
        px = parax(t, x)
        push!(p, string("<line ", atrs("x1" => px, "y1" => y_topo, "x2" => px,
                                       "y2" => y_base, "stroke" => Formato.LINHA,
                                       "stroke-width" => 0.6), "/>"))
        # A primeira marca cai em cima da borda esquerda do painel; centrada, o rótulo
        # invadiria a coluna dos rótulos de y (o "3000" encostando no "0"). Ancorar
        # pela ponta nas duas extremidades resolve sem mexer na faixa do eixo.
        ancora = px - x_esq < 18 ? "start" : x_dir - px < 18 ? "end" : "middle"
        push!(p, texto_px(px, y_base + 8, fx(x); tam = 10.5,
                          cor = Formato.TINTA_FRACA, base = "hanging", ancora))
    end
    for y in ys
        py = paray(t, y)
        push!(p, string("<line ", atrs("x1" => x_esq, "y1" => py, "x2" => x_dir,
                                       "y2" => py, "stroke" => Formato.LINHA,
                                       "stroke-width" => 0.6), "/>"))
        push!(p, texto_px(x_esq - 7, py, fy(y); tam = 10.5,
                          cor = Formato.TINTA_FRACA, ancora = "end"))
    end

    push!(p, caixa_px(x_esq, y_topo, x_dir - x_esq, y_base - y_topo;
                      preenche = "none", traco = Formato.LINHA, largura = 1))

    isempty(titulo) || push!(p, texto_px(x_esq, y_topo - 14, titulo; tam = 13,
                                         cor = Formato.TINTA, ancora = "start"))
    isempty(xlabel) || push!(p, texto_px((x_esq + x_dir) / 2, t.alt - 8, xlabel;
                                         tam = 11, cor = Formato.TINTA_FRACA,
                                         base = "auto"))
    if !isempty(ylabel)
        cy = (y_topo + y_base) / 2
        push!(p, string("<text ", atrs("x" => 13, "y" => cy, "font-size" => 11,
                                       "fill" => Formato.TINTA_FRACA,
                                       "text-anchor" => "middle",
                                       "transform" => "rotate(-90 13 $(svgn(cy)))"),
                        ">", escapa(ylabel), "</text>"))
    end
    return p
end

"Faixa do eixo coberta pela varredura."
function _faixa_x(res)
    xs = [r.x for r in res.rows]
    return (minimum(xs), maximum(xs))
end

"""
    _painel(id, larg, alt) -> (recorte_svg, envolver)

Declara o recorte do painel de plotagem e devolve a função que embrulha as séries nele.

Sem isto a curva sai por cima do título e dos rótulos sempre que o eixo y é limitado —
e ele é: em diâmetros pequenos o SR dispara, e o gráfico existe justamente para mostrar
a banda 3–5, que ficaria achatada num traço se o eixo acompanhasse o pico.
"""
function _painel(id::AbstractString, larg, alt)
    x, y = MARGEM_GRAFICO.esq, MARGEM_GRAFICO.topo
    w = larg - MARGEM_GRAFICO.esq - MARGEM_GRAFICO.dir
    h = alt - MARGEM_GRAFICO.topo - MARGEM_GRAFICO.base
    return (recorte(id, x, y, w, h), corpo -> recortado(id, corpo))
end

"Linha vertical no diâmetro selecionado, mais o marcador em cima da curva."
function _cursor!(p, t, d_sel, y_topo, y_base, ponto, cor_ponto)
    px = parax(t, d_sel)
    push!(p, string("<line ", atrs("x1" => px, "y1" => y_topo, "x2" => px,
                                   "y2" => y_base, "stroke" => Formato.DESTAQUE,
                                   "stroke-width" => 1.4,
                                   "stroke-dasharray" => TRACEJADO), "/>"))
    ponto === nothing && return p
    push!(p, marcador(t, ponto; raio = 5.5, preenche = cor_ponto,
                      traco = "#ffffff", largura = 1.5))
    return p
end

"""
    svg_grafico_envelope(res, x_sel; titulo, xlabel, ylabel, ...) -> String

A grandeza exigida contra o eixo varrido: uma curva fina por caso (cor do caso), a
envelope por cima (grossa), e uma linha vertical no ponto selecionado.

Limitado a `max_curvas` curvas individuais para que 64 casos de canto não virem
espaguete — a envelope continua correta, apenas não se desenha cada canto.
"""
function svg_grafico_envelope(res, x_sel::Real; titulo::AbstractString = "",
                              xlabel::AbstractString = "", ylabel::AbstractString = "",
                              larg::Real = 560.0, alt::Real = 260.0,
                              max_curvas::Int = 12)
    (res === nothing || isempty(res.rows)) &&
        return documento_vazio(larg, alt, "Sem varredura.")

    xlo, xhi = _faixa_x(res)
    ymax = maximum(r.y for r in res.rows)
    t = tela_livre(xlo, 0.0, xhi, ymax * 1.08; larg, alt, margem = MARGEM_GRAFICO)

    p = String[]
    moldura!(p, t, ticks_bonitos(xlo, xhi), ticks_bonitos(0.0, ymax * 1.08);
             titulo, xlabel, ylabel,
             fx = Formato.inteiro, fy = v -> Formato.num(v, 0))

    corte, envolver = _painel("fpso-rec-env", larg, alt)
    push!(p, corte)

    series = String[]
    for i in 1:min(max_curvas, length(res.case_names))
        pts = [(r.x, r.per_case_y[i]) for r in res.rows]
        push!(series, polilinha(t, pts; traco = Formato.cor_caso(i), largura = 1.0))
    end
    push!(series, polilinha(t, [(r.x, r.y) for r in res.rows];
                            traco = Formato.TINTA, largura = 2.6))

    linha = argmin(r -> abs(r.x - x_sel), res.rows)
    _cursor!(series, t, x_sel, MARGEM_GRAFICO.topo, alt - MARGEM_GRAFICO.base,
             (linha.x, linha.y), Formato.DESTAQUE)
    push!(p, envolver(join(series)))

    return documento(t, join(p); fundo = Formato.FUNDO, rotulo = titulo)
end

"""
    svg_grafico_banda(res, x_sel, chave, banda, alvo; titulo, ...) -> String

Um derivado contra o eixo varrido, com a faixa recomendada sombreada. O ponto escolhido
é marcado; fora da banda ele fica vermelho, que é a sinalização mais direta de que o
projeto não fecha ali.

`chave` é o derivado a plotar — `:sr` num vaso, `:v` numa bomba. O eixo y é limitado a
`banda[2]·2,5`: em diâmetros pequenos a esbeltez dispara (`Leff ~ 1/d²`) e achataria a
banda até virar um traço, que é justamente o que o gráfico existe para mostrar.
"""
function svg_grafico_banda(res, x_sel::Real, chave::Symbol,
                           banda::Tuple{<:Real,<:Real}, alvo::Real;
                           titulo::AbstractString = "", xlabel::AbstractString = "",
                           ylabel::AbstractString = "",
                           larg::Real = 560.0, alt::Real = 260.0)
    (res === nothing || isempty(res.rows)) &&
        return documento_vazio(larg, alt, "Sem varredura.")

    valor = r -> get(r.derivados, chave, NaN)
    xlo, xhi = _faixa_x(res)
    alto = min(maximum(valor(r) for r in res.rows), banda[2] * 2.5)
    ytop = max(alto * 1.1, banda[2] * 1.3)
    t = tela_livre(xlo, 0.0, xhi, ytop; larg, alt, margem = MARGEM_GRAFICO)

    p = String[]
    moldura!(p, t, ticks_bonitos(xlo, xhi), ticks_bonitos(0.0, ytop);
             titulo, xlabel, ylabel,
             fx = Formato.inteiro, fy = v -> Formato.num(v, 0))

    corte, envolver = _painel("fpso-rec-banda", larg, alt)
    push!(p, corte)

    series = String[]
    y_lo, y_hi = paray(t, banda[1]), paray(t, banda[2])
    push!(series, caixa_px(MARGEM_GRAFICO.esq, y_hi,
                           larg - MARGEM_GRAFICO.esq - MARGEM_GRAFICO.dir,
                           y_lo - y_hi; preenche = Formato.OK, opacidade = 0.10))
    for (v, cor, estilo, op) in ((banda[1], Formato.OK, TRACEJADO, 0.45),
                                 (banda[2], Formato.OK, TRACEJADO, 0.45),
                                 (alvo, Formato.TINTA_FRACA, PONTILHADO, 0.6))
        push!(series, segmento(t, (xlo, v), (xhi, v); traco = cor, largura = 1,
                               estilo, opacidade = op))
    end

    push!(series, polilinha(t, [(r.x, valor(r)) for r in res.rows];
                            traco = Formato.TINTA, largura = 2.2))

    linha = argmin(r -> abs(r.x - x_sel), res.rows)
    _cursor!(series, t, x_sel, MARGEM_GRAFICO.topo, alt - MARGEM_GRAFICO.base,
             (linha.x, min(valor(linha), ytop)),
             linha.ok ? Formato.OK : Formato.ERRO)
    push!(p, envolver(join(series)))

    return documento(t, join(p); fundo = Formato.FUNDO, rotulo = titulo)
end

"""
    html_legenda_casos(res; max_itens) -> String

Legenda das curvas por caso, com a cor de cada uma, a folga em relação à envelope e a
marca do caso governante.

`unidade` é a da grandeza envelopada, e vem de [`FPSOSiz.requirement_spec`](@ref) — era
um `" m"` escrito aqui, que estava certo enquanto todo equipamento envelopava um
comprimento. A folga de um trocador podia ser área e a de um compressor, potência: o
último lugar em que a interface ainda sabia o nome de uma grandeza.

Sai em HTML, não em SVG: o número de casos muda a cada
dimensionamento, os nomes de caso de canto são longos (`"Faixa [q_oil↑ q_water↓]"`) e
o HTML quebra linha e deixa o texto selecionável.
"""
function html_legenda_casos(res; max_itens::Int = 12, unidade::AbstractString = "")
    res === nothing && return ""
    sufixo = isempty(unidade) ? "" : " " * unidade
    itens = String[]
    for (i, nome) in enumerate(res.case_names)
        i > max_itens && break
        folga = isempty(res.slack) ? "" : "  (+$(Formato.num(res.slack[i]))$sufixo)"
        governa = nome == res.driver_case
        push!(itens, string(
            "<li", governa ? " class=\"governa\"" : "", ">",
            "<span class=\"amostra\" style=\"background:", Formato.cor_caso(i), "\"></span>",
            "<span class=\"nome\">", escapa(nome), escapa(folga), "</span>",
            governa ? "<span class=\"marca\">◀ governa</span>" : "", "</li>"))
    end
    n_extra = length(res.case_names) - min(max_itens, length(res.case_names))
    n_extra > 0 && push!(itens, "<li class=\"resto\">+ $n_extra caso(s) não desenhado(s)</li>")
    return string("<ul class=\"legenda-casos\">", join(itens), "</ul>")
end

"""
    svg_serie_temporal(ts, series; titulo, xlabel, ylabel, larg, alt) -> String

Renderizador de séries temporais do módulo dinâmico (Entrega C.3): eixo de tempo, uma
polilinha por canal, legenda. **É uma função por cima de [`moldura!`](@ref)** — como as
outras deste arquivo, não cita nenhuma grandeza pelo nome: `ts` são os instantes e cada
elemento de `series` é uma `NamedTuple` `(nome, ys[, cor])` já na escala do seu eixo. O
agrupamento por unidade (pressão num painel, aberturas noutro) é de quem chama, que sabe
o que plota. Versão mínima e funcional; o acabamento vem no sprint de design.
"""
function svg_serie_temporal(ts, series; titulo::AbstractString = "",
                            xlabel::AbstractString = "Tempo (s)",
                            ylabel::AbstractString = "",
                            larg::Real = 560.0, alt::Real = 260.0)
    (isempty(ts) || isempty(series)) && return documento_vazio(larg, alt, "Sem série.")
    ys_all = Float64[]
    for s in series, y in s.ys
        isfinite(y) && push!(ys_all, float(y))
    end
    isempty(ys_all) && return documento_vazio(larg, alt, "Sem dados finitos.")
    ylo, yhi = minimum(ys_all), maximum(ys_all)
    yhi <= ylo && (yhi = ylo + 1.0)
    pad = (yhi - ylo) * 0.08
    xlo, xhi = float(first(ts)), float(last(ts))
    xhi <= xlo && (xhi = xlo + 1.0)

    t = tela_livre(xlo, ylo - pad, xhi, yhi + pad; larg, alt, margem = MARGEM_GRAFICO)
    p = String[]
    moldura!(p, t, ticks_bonitos(xlo, xhi), ticks_bonitos(ylo - pad, yhi + pad);
             titulo, xlabel, ylabel,
             fx = v -> Formato.num(v, 0), fy = v -> Formato.num(v, 2))

    corte, envolver = _painel("fpso-rec-serie", larg, alt)
    push!(p, corte)
    linhas = String[]
    for (i, s) in enumerate(series)
        pts = [(float(ts[j]), float(s.ys[j])) for j in eachindex(ts) if isfinite(s.ys[j])]
        isempty(pts) && continue
        push!(linhas, polilinha(t, pts; traco = get(s, :cor, Formato.cor_caso(i)),
                                largura = 1.8))
    end
    push!(p, envolver(join(linhas)))

    # legenda simples no topo direito — uma amostra de cor e o nome do canal
    yl = MARGEM_GRAFICO.topo + 6.0
    for (i, s) in enumerate(series)
        cor = get(s, :cor, Formato.cor_caso(i))
        xL = larg - MARGEM_GRAFICO.dir - 130
        push!(p, string("<line ", atrs("x1" => xL, "y1" => yl, "x2" => xL + 16,
                        "y2" => yl, "stroke" => cor, "stroke-width" => 2.4), "/>"))
        push!(p, texto_px(xL + 21, yl, s.nome; tam = 10, cor = Formato.TINTA_FRACA,
                          ancora = "start"))
        yl += 14.0
    end
    return documento(t, join(p); fundo = Formato.FUNDO, rotulo = titulo)
end
