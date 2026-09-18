"""
Paleta e formatação numérica PT-BR.

Um só lugar decide cor e formato. As cores das fases são as mesmas no desenho do vaso,
na seção transversal, na legenda e nos gráficos — é o que faz a tela ler como um
sistema só, e é o que permite trocar a identidade visual depois sem caçar literais.

As cores saem daqui em **hexadecimal CSS**, e são as mesmas do tema Makie anterior,
convertidas de `RGBf(0…1)` para `#rrggbb`. `public/app.css` repete os mesmos valores em
`:root`, e um teste em `smoke.jl` confere que os dois lados não divergiram — a folha de
estilo não tem como importar Julia, então a duplicação é vigiada em vez de proibida.
"""

module Formato

using Printf

# ---------------------------------------------------------------------------
# Paleta
#
# Há DUAS paletas aqui, e a distinção é deliberada:
#
# * **Chrome** (`FUNDO`…`DESTAQUE`) — a tinta da interface. Desde a adoção do design
#   system "Industry" estes valores são tokens dele (`--color-bg`, `--color-text`,
#   `--color-neutral-300/700`, `--color-accent-700`), para que a figura e a página em
#   volta dela não fiquem em dois azuis diferentes.
#
# * **Fases e status** (`OK`…`AGUA_ZONA`) — tinta de DADO, e por isso NÃO vêm do DS.
#   O "Industry" é um esquema mono em azul-aço; recolorir óleo e água nele apagaria a
#   única coisa que essas cores existem para dizer, que é qual fase é qual. Do mesmo
#   jeito, verde/vermelho de status significam aprovado/reprovado, não decoração.
#
# O `DESTAQUE` é o passo 700 da rampa do acento, e não o acento base: o próprio guia do
# sistema manda usar um passo profundo para texto em corpo de parágrafo, porque o acento
# base contra este fundo dá ~3:1 — suficiente para ícone e chrome, não para número que
# se lê.
# ---------------------------------------------------------------------------
const FUNDO       = "#f2f2f3"   # DS --color-bg
const PAINEL      = "#ffffff"   # fundo do desenho: papel branco sob traço técnico
const TINTA       = "#1d1f20"   # DS --color-text
const TINTA_FRACA = "#5d5d60"   # DS --color-neutral-700
const LINHA       = "#d4d4d7"   # DS --color-neutral-300
const DESTAQUE    = "#416180"   # DS --color-accent-700

const OK     = "#16804a"
const ALERTA = "#b47b0b"
const ERRO   = "#ba2929"

# Fases — usadas no desenho, na seção e nos gráficos.
# A variante `_ZONA` é o preenchimento da área (mais clara, translúcida); a constante
# sem sufixo é a da linha e do rótulo, que precisa de contraste sobre a área.
const GAS            = "#d9e2ec"
const GAS_ZONA       = "#d9e2ec"
const GAS_ZONA_OP    = 0.85
const OLEO           = "#845f29"
const OLEO_ZONA      = "#a47938"
const OLEO_ZONA_OP   = 0.88
const AGUA           = "#346fa3"
const AGUA_ZONA      = "#4484ba"
const AGUA_ZONA_OP   = 0.88
const ACO            = "#5c636c"
const INTERNO        = "#4a515a"

"Cor de cada caso nos gráficos (curvas finas), ciclando."
const CASOS = ["#8da0cb", "#cb9d8d", "#92bfa0", "#c792bf", "#d8bf82", "#8cbfc7"]

cor_caso(i::Integer) = CASOS[mod1(i, length(CASOS))]

# ---------------------------------------------------------------------------
# Formatação PT-BR (vírgula decimal, ponto de milhar)
# ---------------------------------------------------------------------------

"""
    num(x, casas = 2) -> String

Formata com vírgula decimal. `NaN`/`Inf` viram travessão, para que a tela nunca
mostre "NaN" ao usuário.
"""
function num(x::Real, casas::Integer = 2)
    isfinite(x) || return "—"
    s = Printf.format(Printf.Format("%.$(casas)f"), x)
    return replace(s, '.' => ',')
end

"""
    inteiro(x) -> String

Inteiro com ponto de milhar a partir de 5 dígitos: `5500 → "5500"`,
`16508 → "16.508"`.

O corte em 10.000 é deliberado. Em PT-BR o separador de milhar é o ponto, então
"6.300 mm" é ortograficamente correto — mas num campo de diâmetro, ao lado de
números com vírgula decimal como "3,93", ele se lê como 6,3. Diâmetros de vaso vivem
na casa dos milhares; deixá-los sem separador elimina a ambiguidade sem prejudicar a
legibilidade dos números realmente grandes.
"""
function inteiro(x::Real)
    isfinite(x) || return "—"
    n = round(Int, x)
    abs(n) < 10_000 && return string(n)
    s = string(abs(n))
    partes = String[]
    while length(s) > 3
        pushfirst!(partes, s[end-2:end]); s = s[1:end-3]
    end
    pushfirst!(partes, s)
    return (n < 0 ? "-" : "") * join(partes, ".")
end

"Lê um número aceitando vírgula ou ponto como separador decimal."
function parse_num(s::AbstractString)
    t = strip(replace(s, ' ' => ""))
    isempty(t) && return nothing
    # "1.234,5" → "1234.5" ; "1234,5" → "1234.5" ; "1234.5" → "1234.5"
    if occursin(',', t)
        t = replace(t, '.' => "")
        t = replace(t, ',' => '.')
    end
    return tryparse(Float64, t)
end

"""
    casas_de(spec) -> Int

Casas decimais adequadas à ordem de grandeza do parâmetro. Vinha de `dashboard.jl`;
agora serve o formulário HTML, que recebe os valores já formatados do servidor.
"""
casas_de(spec) = spec.default >= 100 ? 1 :
                 spec.default >= 1   ? 2 : 4

# NOTA: o número para dentro de um atributo de SVG NÃO se formata aqui. Existia um
# `svgnum` neste módulo, nunca chamado, com arredondamento diferente do `svgn` de
# `desenho/svg.jl` — que é quem de fato escreve os atributos. Duas regras para a mesma
# coisa é exatamente o que este módulo existe para impedir; a que sobrou é a de svg.jl,
# ao lado de quem a usa.

end # module Formato
