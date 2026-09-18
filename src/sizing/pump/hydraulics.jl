"""
Hidráulica de linha — as quatro relações que Moran (*Pump Sizing*, CEP dez/2016) usa
para montar a carga do sistema, mais a Antoine que ele usa para o NPSH.

Vive separado de `moran.jl` pelo mesmo motivo que `gas_capacity.jl` vive separado dos
dois vasos: **são equações de física, não de equipamento.** Colebrook-White e
Darcy-Weisbach servirão a qualquer linha que o programa venha a dimensionar, e
mantê-las aqui deixa o método do Sprint 8 com o que é dele — a sequência de cálculo e
o critério de escolha.

# Como as equações foram lidas

As fórmulas do artigo são **imagem** dentro do PDF, e o PDF é cifrado com `copy:no`: o
texto extraível traz a prosa e as tabelas, nunca as equações. Até o Sprint 8 as formas
abaixo foram recuperadas da prosa — que as descreve sem ambiguidade, nomeando cada
símbolo, a unidade e a faixa de validade — e conferidas contra os dois números que o
artigo publica.

Na fase de validação física as sete equações foram **lidas diretamente**, rasterizando as
páginas (`pdftoppm`, que usa a permissão `print:yes` que o documento concede) e
conferindo símbolo por símbolo. Todas as sete fecham com o que estava implementado; o
registro linha a linha está em `docs/validacao/01-bomba-moran.md`.

Isso derrubou uma limitação que este cabeçalho declarava: os coeficientes da Tabela 2
(Zigrang-Sylvester e Haaland) **são** legíveis, e as duas formas estão impressas por
extenso com as faixas de rugosidade de cada uma. Continuam fora do programa, mas agora
por escolha e não por indisponibilidade — Colebrook-White é a que o autor declara
preferir, e acrescentar correlação alternativa não melhora a validação de nenhuma.

# O que é do artigo e o que não é

| relação | fonte |
|---|---|
| perda localizada `hf = k·v²/(2g)` | Moran, **Eq. (1)**, p. 40 |
| Colebrook-White (fator de Darcy) | Moran, **Eq. (2)**, p. 41 — declarada para `Re > 4000` |
| Reynolds `Re = ρvD/µ` | Moran, **Eq. (3)**, p. 41 |
| Darcy-Weisbach `Δp/L = f·ρv²/(2D)` | Moran, **Eq. (4)**, p. 41 |
| Antoine `log₁₀ Pv[bar] = A − B/(C+T[K])` | Moran, **Eq. (5)** e Tabela 3, p. 41 |
| NPSH `= P₀/(ρg) + h₀ − h_Sf − Pv/(ρg)` | Moran, **Eq. (6)**, p. 41 |
| potência `P = QρgH/(3,6×10⁶η)` | Moran, **Eq. (7)**, p. 42 |
| `f = 64/Re` no regime laminar | **não é do artigo** — ver [`darcy_friction`](@ref) |

O `g = 9,81 m/s²` é o valor que o artigo declara ao definir a Eq. (1) ("g is the
acceleration due to gravity (9.81 m/sec²)"), e é o que se usa; o padrão internacional é
9,80665, e a diferença de 0,03 % não muda nenhuma decisão de diâmetro.
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
    flow_regime(re, k) -> (regime::Symbol, confiavel::Bool)

Em que regime o escoamento está, e se a correlação daquele regime **vale** ali.

Existe separada de [`darcy_friction`](@ref) porque a classificação é consultada em dois
lugares — o cálculo do `f` e o memorial, que tem de citar a equação que de fato produziu
o número. Duas classificações independentes divergiriam no dia em que uma das duas
fronteiras mudasse de valor no TOML, e a divergência apareceria como um memorial citando
Colebrook-White sobre um `f` de Hagen-Poiseuille — que foi exatamente o defeito que a
fase de validação encontrou aqui.

`confiavel = false` na zona de transição não é falha de convergência: é a afirmação de
que **nenhuma** das duas correlações implementadas vale naquele `Re`.
"""
function flow_regime(re::Real, k::AbstractDict)
    (isfinite(re) && re > 0) || return (:indefinido, false)
    re <= float(k[:reynolds_laminar_max])   && return (:laminar, true)
    re >= float(k[:reynolds_turbulent_min]) && return (:turbulento, true)
    return (:transicao, false)
end

"""
    friction_equation(regime) -> (fonte, forma)

A citação que o memorial tem de imprimir ao lado do `f` **daquele** regime: o par
(equação, forma algébrica) da relação que produziu o número.

Carimbar "Colebrook" sobre um `f` que veio de `64/Re` manda o leitor conferir a conta na
equação errada. Não muda nenhum número e por isso não aparece em teste de valor — é
defeito de atribuição, e é o `test/golden_moran.jl` que o fixa.

**O turbulento cita o NÚMERO da equação; o laminar, o nome.** A assimetria é a própria
proveniência: Colebrook-White é a **Eq. (2)** do artigo (p. 41), então o memorial manda o
revisor ao número que ele vai achar lá; `f = 64/Re` **não é do artigo** — é
Hagen-Poiseuille, acrescentada por este programa —, e dar-lhe um número de equação seria
mandar procurar na fonte uma equação que ela não tem. Ver §3 de
`docs/validacao/01-bomba-moran.md`.

**A `fonte` é curta de propósito.** `linha_memorial` (em `app/src/report.jl`) alinha esse
campo em 10 colunas. "Hagen-Poiseuille" tem 16 e colaria no nome da variável — daí o
sobrenome só. O nome inteiro vai na `forma`, que é a última coluna e não tem largura fixa.
"""
friction_equation(regime::Symbol) =
    regime === :laminar    ? ("Hagen",
                              "f = 64/Re — Hagen-Poiseuille, exata no laminar; " *
                              "NÃO consta do artigo") :
    regime === :indefinido ? ("—", "regime indefinido: Re não é número positivo") :
    ("Eq. 2", "1/√f = −2log₁₀(ε/3,7D + 2,51/(Re√f)) — Colebrook-White")

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
    regime, confiavel = flow_regime(re, k)
    regime === :indefinido && return (NaN, regime, false)
    regime === :laminar &&
        return (float(k[:laminar_coefficient]) / re, regime, confiavel)

    f, ok = colebrook_white(re, rel_rough; f0 = float(k[:colebrook_initial]),
                            tol = float(k[:colebrook_tolerance]),
                            maxiter = Int(k[:colebrook_max_iter]))
    ok || return (f, :nao_convergiu, false)
    return (f, regime, confiavel)
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
