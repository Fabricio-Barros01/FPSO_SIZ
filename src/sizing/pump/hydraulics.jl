"""
Hidráulica de linha — as quatro relações que Moran (*Pump Sizing*, CEP dez/2016) usa
para montar a carga do sistema, mais a Antoine que ele usa para o NPSH.

Vive separado de `moran.jl` pelo mesmo motivo que `gas_capacity.jl` vive separado dos
dois vasos: **são equações de física, não de equipamento.** Colebrook-White e
Darcy-Weisbach servirão a qualquer linha que o programa venha a dimensionar, e
mantê-las aqui deixa o método do Sprint 8 com o que é dele — a sequência de cálculo e
o critério de escolha.

# Uma limitação da fonte, declarada

As equações do artigo são **imagem** dentro do PDF: o texto extraível traz a prosa e as
tabelas, não as fórmulas. As formas abaixo foram recuperadas da prosa, que as descreve
sem ambiguidade (nomeia cada símbolo, a unidade e a faixa de validade), e conferidas
contra os dois números que o artigo publica: a Antoine da Tabela 3 (água a 30 °C) e a
leitura do nomograma da Figura 3. O que **não** foi possível recuperar são os
coeficientes da Tabela 2 (Zigrang-Sylvester e Haaland), que também são imagem e não têm
número conferível no texto — por isso só Colebrook-White está implementada, que é a que
o autor declara preferir.

# O que é do artigo e o que não é

| relação | fonte |
|---|---|
| perda localizada `hf = k·v²/(2g)` | Moran, "Determining frictional losses through fittings" |
| Reynolds `Re = ρvD/µ` | Moran, junto de Colebrook-White |
| Colebrook-White (fator de Darcy) | Moran, declarada para `Re > 4000` |
| Darcy-Weisbach `Δp = f·(L/D)·(ρv²/2)` | Moran |
| Antoine `log₁₀ Pv[bar] = A − B/(T[K]+C)` | Moran, Tabela 3 |
| `f = 64/Re` no regime laminar | **não é do artigo** — ver [`darcy_friction`](@ref) |

O `g = 9,81 m/s²` é o valor que o artigo declara ao definir a perda localizada, e é o
que se usa; o padrão internacional é 9,80665, e a diferença de 0,03 % não muda nenhuma
decisão de diâmetro.
"""

"""
    reynolds_pipe(rho, v, d_m, mu) -> Re

`Re = ρ·v·D/µ`, com `rho` em kg/m³, `v` em m/s, `d_m` em m e `mu` em Pa·s.

Homônima em espírito de [`reynolds`](@ref) de `drag.jl`, e deliberadamente **não** a
mesma função: aquela é o Reynolds de uma gotícula caindo (comprimento característico =
diâmetro da gota, velocidade = velocidade terminal), esta é o de um escoamento em duto.
Unificá-las só produziria uma função com dois significados.
"""
reynolds_pipe(rho::Real, v::Real, d_m::Real, mu::Real) = rho * v * d_m / mu

"""
    colebrook_white(re, rel_rough; f0, tol, maxiter) -> (f, convergiu)

Fator de atrito de **Darcy** pela aproximação de Colebrook-White,

    1/√f = −2·log₁₀( ε/(3,7·D) + 2,51/(Re·√f) )

resolvida por ponto fixo em `x = 1/√f`. O artigo recomenda resolvê-la iterativamente
("the Goal Seek function in Excel does this quickly and easily"); a forma em `x` é
contrativa e converge em poucas passagens sem precisar de derivada.

`rel_rough` é `ε/D` (adimensional) — a rugosidade **já dividida** pelo diâmetro, para
que a função não precise saber em que unidade o chamador guarda as duas.

Devolve também se convergiu: um `f` que não convergiu é um número plausível vindo de um
laço que não fechou, e o memorial precisa poder dizer isso em vez de imprimi-lo como se
fosse resultado. Ver o par `converge_drag` em `drag.jl`, que segue a mesma regra.

**Não confundir com o fator de Fanning**, que vale um quarto deste — o artigo dedica um
parágrafo ao engano, porque ele é silencioso: erra a perda por 4× sem produzir nada
absurdo na tela.
"""
function colebrook_white(re::Real, rel_rough::Real; f0::Real = 0.02,
                         tol::Real = 1e-10, maxiter::Int = 60)
    (isfinite(re) && re > 0) && return _colebrook_loop(float(re), float(rel_rough),
                                                       float(f0), float(tol), maxiter)
    return (NaN, false)
end

function _colebrook_loop(re::Float64, rel::Float64, f0::Float64, tol::Float64,
                         maxiter::Int)
    x = 1.0 / sqrt(f0)
    for _ in 1:maxiter
        novo = -2.0 * log10(rel / 3.7 + 2.51 * x / re)
        novo > 0 || return (NaN, false)
        abs(novo - x) <= tol * max(1.0, abs(novo)) && return (1.0 / novo^2, true)
        x = novo
    end
    return (1.0 / x^2, false)
end

"""
    darcy_friction(re, rel_rough, k) -> (f, regime, confiavel)

O fator de Darcy no regime em que o escoamento de fato está, e o nome do regime.

**A parte laminar não é do artigo.** Moran declara Colebrook-White (e as duas
alternativas da Tabela 2) válidas para `Re > 4000` e não diz o que fazer abaixo disso —
razoável num artigo cuja regra de bolso é justamente manter a velocidade em 1–1,5 m/s,
onde uma linha de água nunca é laminar. Mas o programa aceita qualquer viscosidade, e
um óleo pesado numa linha estreita cai em regime laminar com facilidade. As opções eram
recusar o cálculo, ou extrapolar Colebrook-White para fora da faixa em que a fonte a
declara — que produziria um `f` errado **sem nada denunciando**, porque a fórmula
devolve número em qualquer `Re`.

Optou-se por `f = 64/Re` (Hagen-Poiseuille), que é exata para escoamento laminar
plenamente desenvolvido em duto circular, com o coeficiente vindo do TOML e o regime
carimbado no rastro de cálculo. Entre `Re_lam` e `Re_turb` não há correlação nenhuma
que valha: a zona de transição é instável por natureza. Ali usa-se Colebrook-White e
`confiavel = false`, e é o memorial que avisa.
"""
function darcy_friction(re::Real, rel_rough::Real, k::AbstractDict)
    re_lam  = float(k[:reynolds_laminar_max])
    re_turb = float(k[:reynolds_turbulent_min])
    (isfinite(re) && re > 0) || return (NaN, :indefinido, false)

    if re <= re_lam
        return (float(k[:laminar_coefficient]) / re, :laminar, true)
    end
    f, ok = colebrook_white(re, rel_rough; f0 = float(k[:colebrook_initial]),
                            tol = float(k[:colebrook_tolerance]),
                            maxiter = Int(k[:colebrook_max_iter]))
    ok || return (f, :nao_convergiu, false)
    return re >= re_turb ? (f, :turbulento, true) : (f, :transicao, false)
end

"""
    straight_run_head(f, l_m, d_m, v, g) -> m

Perda de carga em trecho reto, por Darcy-Weisbach. O artigo escreve a equação em queda
de **pressão** (`Δp = f·(L/D)·ρv²/2`); dividida por `ρg` ela vira metros de coluna do
próprio fluido, que é a unidade em que o artigo soma tudo ("mwg", metres water gauge) e
em que a curva do sistema se compara com a curva da bomba.
"""
straight_run_head(f::Real, l_m::Real, d_m::Real, v::Real, g::Real) =
    d_m > 0 ? f * (l_m / d_m) * v^2 / (2 * g) : Inf

"""
    fittings_head(k_total, v, g) -> m

Perda localizada pelo método dos k-values: `hf = k·v²/(2g)`, com `k` a **soma** dos
coeficientes de todas as válvulas, curvas e tês do trecho. Os valores por peça estão na
Tabela 1 do artigo e chegam aqui já somados, porque contá-los é leitura de P&ID, não
cálculo.
"""
fittings_head(k_total::Real, v::Real, g::Real) = k_total * v^2 / (2 * g)

"""
    antoine_pressure(a, b, c, t_k) -> Pa

Pressão de vapor pela equação de Antoine na forma do NIST, `log₁₀ Pv[bar] = A − B/(T+C)`
com `T` em kelvin — que é a forma cujos coeficientes o artigo manda buscar no
webbook.nist.gov, e a que reproduz a Tabela 3 (água a 30 °C → 4243,81 Pa).

O resultado sai em **pascal**, não em bar: é o que a expressão do NPSH consome, e
converter uma vez aqui evita um `×10⁵` solto no meio da física.
"""
antoine_pressure(a::Real, b::Real, c::Real, t_k::Real) =
    10.0^(a - b / (t_k + c)) * 1.0e5
