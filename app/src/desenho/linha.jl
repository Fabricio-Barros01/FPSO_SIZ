"""
Os esquemas dos dois equipamentos que não são vasos: a linha de recalque da bomba e o
casco-e-tubos do trocador.

Nenhum dos dois é um desenho **de escala**, e a diferença em relação a `vaso.jl` é
deliberada. A elevação de um vaso mostra a proporção real — `Lss` contra `d` é o que a
esbeltez significa, e ver o vaso comprido é ver a esbeltez. Uma linha de recalque não
tem proporção que valha a pena olhar: 120 m de tubo de 250 mm desenhados em escala são
um traço. O que ela tem de comunicar é **topologia com as cotas em cima** — de onde sai,
para onde vai, o que sobe e o que se perde no caminho.

Então estes dois são diagramas: geometria fixa, números do resultado escritos nela. É a
mesma decisão que qualquer folha de processo toma, e é o que faz o desenho continuar
legível quando o resultado muda de ordem de grandeza.

`vaso.jl` continua sendo o desenho proporcional dos três vasos — os dois arquivos não
se sobrepõem.
"""

# ---------------------------------------------------------------------------
# Bomba: reservatório de sucção, bomba, linha de recalque, destino
# ---------------------------------------------------------------------------

"""
    svg_linha_bomba(d; larg) -> String

Esquema hidráulico da linha, com as cotas que o dimensionamento produziu: desnível,
carga estática, perda de carga, carga total e NPSH disponível.

`d` é o dicionário de derivados do ponto selecionado, mais o que o cartão já mostra.
Recebe o dicionário e não o resultado inteiro porque o cursor da tela move o ponto sem
refazer o dimensionamento — a figura acompanha o cursor, como a do vaso.
"""
function svg_linha_bomba(d::AbstractDict, dn_mm::Real, h_total::Real; larg = 900.0)
    alt = larg * 0.42
    t = Tela(0.0, 0.0, larg / 100.0, alt / 100.0, 0.0, 0.0, float(larg), float(alt))
    px = (x, y) -> para(t, (x, y))

    tem = isfinite(dn_mm) && isfinite(h_total)
    tem || return documento_vazio(larg, alt, "Sem dimensionamento.")

    p = String[]

    # --- os dois reservatórios, em cotas diferentes
    y_suc, y_rec = 26.0, 68.0
    push!(p, _tanque!(t, 4.0, y_suc, 17.0, 20.0, "sucção"))
    push!(p, _tanque!(t, 79.0, y_rec, 17.0, 20.0, "recalque"))

    # --- a linha: sucção horizontal, bomba, recalque subindo
    x_bomba = 33.0
    linha = [(21.0, y_suc + 5), (x_bomba - 5, y_suc + 5)]
    push!(p, polilinha(t, linha; traco = Formato.ACO, largura = 3.0))
    push!(p, polilinha(t, [(x_bomba + 5, y_suc + 5), (52.0, y_suc + 5),
                           (52.0, y_rec + 5), (79.0, y_rec + 5)];
                       traco = Formato.ACO, largura = 3.0))

    # --- a bomba: círculo com o triângulo de fluxo, o símbolo de folha de processo
    cx, cy = para(t, (x_bomba, y_suc + 5))
    r = 5.0 * t.escx
    push!(p, string("<circle ", atrs("cx" => cx, "cy" => cy, "r" => r,
                                     "fill" => Formato.PAINEL,
                                     "stroke" => Formato.DESTAQUE,
                                     "stroke-width" => 2.0), "/>"))
    push!(p, string("<polygon ", atrs(
        "points" => join([string(svgn(cx - r * 0.45), ",", svgn(cy - r * 0.55)),
                          string(svgn(cx - r * 0.45), ",", svgn(cy + r * 0.55)),
                          string(svgn(cx + r * 0.6), ",", svgn(cy))], " "),
        "fill" => Formato.DESTAQUE), "/>"))
    push!(p, texto_px(cx, cy + r + 11, "$(Formato.inteiro(dn_mm)) mm";
                      tam = 11, cor = Formato.TINTA, peso = "600"))

    # --- cota do desnível estático, entre as duas superfícies
    push!(p, _cota_vertical!(t, 60.0, y_suc + 5, y_rec + 5,
                             "h_est = $(_m(d, :h_est))"))
    # --- a perda de carga, marcada sobre o trecho de recalque
    push!(p, texto(t, (65.0, y_rec + 11),
                   "perda de carga  $(_m(d, :h_atrito))";
                   tam = 11, cor = Formato.ALERTA))
    push!(p, texto(t, (26.0, y_suc + 13),
                   "NPSH disp.  $(_m(d, :npsh))";
                   tam = 11, cor = Formato.OK, ancora = "start"))

    # --- a carga total, em destaque junto da bomba
    push!(p, texto(t, (x_bomba, 8.0),
                   "H = $(Formato.num(h_total)) m   ·   " *
                   "v = $(_num(d, :v)) m/s   ·   P = $(_num(d, :potencia)) kW";
                   tam = 13, cor = Formato.TINTA, ancora = "start", peso = "600"))

    return documento(t, join(p); fundo = Formato.FUNDO,
                     rotulo = "Esquema da linha: reservatório de sucção, bomba e " *
                              "linha de recalque, com as cotas do dimensionamento")
end

"Um reservatório: caixa aberta em cima com a superfície de líquido hachurada."
function _tanque!(t::Tela, x, y, w, h, nome)
    p = String[]
    x0, y0 = para(t, (x, y + h))
    push!(p, caixa_px(x0, y0, w * t.escx, h * t.escy;
                      preenche = Formato.PAINEL, traco = Formato.ACO, largura = 1.6))
    # o líquido ocupa a parte de baixo; a linha de cima é a superfície livre
    yl, = para(t, (x, y + h * 0.62))
    ysup = paray(t, y + h * 0.62)
    push!(p, caixa_px(x0, ysup, w * t.escx, paray(t, y) - ysup;
                      preenche = Formato.AGUA_ZONA, opacidade = 0.35))
    push!(p, segmento(t, (x, y + h * 0.62), (x + w, y + h * 0.62);
                      traco = Formato.AGUA, largura = 1.4))
    push!(p, texto(t, (x + w / 2, y - 6.0), nome; tam = 11, cor = Formato.TINTA_FRACA))
    return join(p)
end

"Cota vertical com setas nas pontas e o rótulo no meio."
function _cota_vertical!(t::Tela, x, y1, y2, rotulo)
    p = String[]
    push!(p, segmento(t, (x, y1), (x, y2); traco = Formato.TINTA_FRACA, largura = 1.0))
    for y in (y1, y2)
        push!(p, segmento(t, (x - 1.6, y), (x + 1.6, y);
                          traco = Formato.TINTA_FRACA, largura = 1.0))
    end
    push!(p, texto(t, (x + 2.5, (y1 + y2) / 2), rotulo;
                   tam = 11, cor = Formato.TINTA, ancora = "start"))
    return join(p)
end

# ---------------------------------------------------------------------------
# Trocador: casco, feixe, chicanas e as quatro temperaturas
# ---------------------------------------------------------------------------

"""
    svg_trocador(d, l_m; larg) -> String

Corte longitudinal esquemático de um casco-e-tubos: casco, espelhos, chicanas
alternadas e os quatro bocais, com as grandezas do ponto selecionado escritas em cima.

O número de tubos desenhados é fixo em cinco — desenhar os 230 reais faria um bloco
preto. O que a figura comunica é o **arranjo** (contracorrente, chicanas cruzando o
feixe), e o número real está escrito ao lado.
"""
function svg_trocador(d::AbstractDict, l_m::Real, n_passes::Int; larg = 900.0)
    alt = larg * 0.34
    t = Tela(0.0, 0.0, larg / 100.0, alt / 100.0, 0.0, 0.0, float(larg), float(alt))

    isfinite(l_m) || return documento_vazio(larg, alt, "Sem dimensionamento.")

    p = String[]
    x0, x1 = 10.0, 90.0
    yb, yt = 24.0, 62.0

    # --- casco
    push!(p, caixa_px(parax(t, x0), paray(t, yt), (x1 - x0) * t.escx,
                      (yt - yb) * t.escy;
                      preenche = Formato.GAS_ZONA, opacidade = 0.55,
                      traco = Formato.ACO, largura = 2.0))
    # --- espelhos
    for x in (x0 + 3.0, x1 - 3.0)
        push!(p, segmento(t, (x, yb), (x, yt); traco = Formato.ACO, largura = 2.4))
    end
    # --- chicanas alternadas, cortando 25 % do casco (Tabela 3.1)
    for (i, x) in enumerate(range(x0 + 12.0, x1 - 12.0; length = 5))
        alto = i % 2 == 1
        push!(p, segmento(t, (x, alto ? yb : yt - 0.25 * (yt - yb)),
                          (x, alto ? yb + 0.75 * (yt - yb) : yt);
                          traco = Formato.INTERNO, largura = 1.6))
    end
    # --- feixe: cinco tubos, ou dez em dois passes
    ys = range(yb + 4.0, yt - 4.0; length = n_passes == 2 ? 6 : 5)
    for (i, y) in enumerate(ys)
        push!(p, segmento(t, (x0 + 3.0, y), (x1 - 3.0, y);
                          traco = Formato.DESTAQUE, largura = 1.6,
                          opacidade = 0.75))
        n_passes == 2 && i == 3 && push!(p, texto(t, ((x0 + x1) / 2, y + 2.0),
                                                  "2 passes"; tam = 9.5,
                                                  cor = Formato.TINTA_FRACA))
    end

    # --- bocais: tubo entra e sai pelas cabeças, casco pelos flancos
    push!(p, _bocal!(t, x0 - 6.0, (yb + yt) / 2, 6.0, 0.0, "tubo entra", Formato.DESTAQUE))
    push!(p, _bocal!(t, x1, (yb + yt) / 2, 6.0, 0.0, "tubo sai", Formato.DESTAQUE))
    push!(p, _bocal!(t, x1 - 14.0, yt, 0.0, 7.0, "casco entra", Formato.OLEO))
    push!(p, _bocal!(t, x0 + 14.0, yb - 7.0, 0.0, 7.0, "casco sai", Formato.OLEO))

    # --- cota do comprimento
    push!(p, segmento(t, (x0 + 3.0, 14.0), (x1 - 3.0, 14.0);
                      traco = Formato.TINTA_FRACA, largura = 1.0))
    push!(p, texto(t, ((x0 + x1) / 2, 10.0),
                   "L = $(Formato.num(l_m)) m   ·   " *
                   "$(Formato.inteiro(get(d, :n_total, NaN))) tubos   ·   " *
                   "feixe $(Formato.inteiro(get(d, :d_casco, NaN))) mm";
                   tam = 12, cor = Formato.TINTA, peso = "600"))
    push!(p, texto(t, ((x0 + x1) / 2, 72.0),
                   "U = $(_num(d, :u)) W/m²K   ·   A = $(_num(d, :area)) m²   ·   " *
                   "ΔT_lm = $(_num(d, :dt_lm)) K   ·   F = $(Formato.num(get(d, :f, NaN), 3))";
                   tam = 12, cor = Formato.TINTA))

    return documento(t, join(p); fundo = Formato.FUNDO,
                     rotulo = "Corte esquemático do casco-e-tubos, com chicanas, o " *
                              "feixe e as grandezas do dimensionamento")
end

"Um bocal: traço curto saindo do casco, com o rótulo."
function _bocal!(t::Tela, x, y, dx, dy, nome, cor)
    p = [segmento(t, (x, y), (x + dx, y + dy); traco = cor, largura = 2.6)]
    horizontal = dx != 0
    push!(p, texto(t, (x + dx / 2, y + dy + (horizontal ? 3.5 : (dy > 0 ? 3.0 : -3.0))),
                   nome; tam = 9.5, cor = Formato.TINTA_FRACA))
    return join(p)
end

# ---------------------------------------------------------------------------

"Um derivado como texto com unidade de metro, ou travessão."
_m(d::AbstractDict, k::Symbol) =
    isfinite(get(d, k, NaN)) ? Formato.num(d[k]) * " m" : "—"

"Um derivado como número, ou travessão."
_num(d::AbstractDict, k::Symbol) =
    isfinite(get(d, k, NaN)) ? Formato.num(d[k]) : "—"
