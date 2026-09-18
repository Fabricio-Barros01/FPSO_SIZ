"""
A simbologia matemática do memorial: um subconjunto de LaTeX convertido em **MathML**,
aqui, em Julia, sem script no documento e sem fonte nova.

## Por que MathML, e não uma biblioteca

O documento gerado por [`documento_html`](@ref) não tem script nenhum — é a propriedade
que o faz imprimir igual em qualquer navegador e abrir de um arquivo solto, sem servidor.
Uma biblioteca de renderização (KaTeX, MathJax) desfaria exatamente isso: passaria a
exigir JavaScript para que a equação aparecesse, e mais ~1 MB de fontes próprias dentro
do bundle do PackageCompiler.

MathML Core é nativo nos três motores desde 2023, não precisa de fonte própria e imprime.
O custo é este arquivo; o benefício é o documento continuar sendo um arquivo que se abre.

## O que vinha antes, e por que não servia

`EquacaoDoc.notacao` é a equação em texto Unicode inline, e ela **continua** — é o que o
`.txt` exportado grava e o painel da tela mostra, onde não há como desenhar fração.

O que não dá para fazer em texto de uma linha é o que a folha 03 do handoff pede: fração
empilhada, radical cobrindo o radicando, expoente sobrescrito de verdade. Em texto,
`√((ρ_l − ρ_g)/ρ_g)` sai como `[ ... ]^(1/2)` — que é notação de código, exatamente o que
o handoff proíbe na faixa de equação.

## O subconjunto aceito

Fechado e declarado. **Comando ou caractere fora desta lista lança erro** — é a mesma
regra de [`resolver`](@ref) com token não resolvido: o documento não sai com buraco
silencioso, porque uma equação que falhou em silêncio vira uma faixa vazia num documento
assinado.

| construção | escreve-se | sai |
|---|---|---|
| fração | `\\frac{a}{b}` | `<mfrac>` |
| raiz | `\\sqrt{x}`, `\\sqrt[3]{x}` | `<msqrt>`, `<mroot>` |
| subscrito / expoente | `V_t`, `d^2`, `T_{lm}`, `Re^{0,5}` | `<msub>`, `<msup>`, `<msubsup>` |
| delimitador escalável | `\\left[ … \\right]` | `<mo stretchy="true">` |
| grego | `\\rho`, `\\mu`, `\\Delta`, `\\beta`, … | `<mi>` |
| operador | `\\cdot`, `\\times`, `\\le`, `\\ge`, `\\approx`, `\\pm` | `<mo>` |
| função | `\\log`, `\\ln`, `\\arccos`, `\\min`, … | `<mi>` sem itálico |
| texto | `\\text{quentes}` | `<mtext>` |
| romano | `\\mathrm{CP}` | `<mi>` sem itálico |

### Duas divergências deliberadas em relação ao LaTeX

1. **Decimal com vírgula.** `0,0036` é um número só. Em LaTeX a vírgula é pontuação e se
   escreveria `0{,}0036`; aqui o documento é em português e a vírgula decimal é a forma
   corrente das fontes (Stewart & Arnold traduzido, Alves & Komesu). Obrigar `{,}` em
   ~74 equações seria ruído de autoria sem leitor que o peça.

2. **Letras seguidas são um identificador só.** `Re` sai `<mi>Re</mi>`, não `R·e`. Em
   LaTeX puro seria preciso `\\mathrm{Re}` em todo lugar. A notação de engenharia é cheia
   de símbolos de duas letras — `Re`, `SG`, `CP`, `NPSH` —, e a multiplicação nestas
   equações é sempre explícita (`\\cdot`), então não há ambiguidade a desfazer.
"""

# ---------------------------------------------------------------------------
# O vocabulário
# ---------------------------------------------------------------------------

"Letras gregas e outros símbolos que viram `<mi>` (variável, itálico)."
const MATH_SIMBOLOS = Dict{String,String}(
    "alpha" => "α", "beta" => "β", "gamma" => "γ", "delta" => "δ",
    "epsilon" => "ε", "varepsilon" => "ε", "zeta" => "ζ", "eta" => "η",
    "theta" => "θ", "kappa" => "κ", "lambda" => "λ", "mu" => "µ",
    "nu" => "ν", "xi" => "ξ", "pi" => "π", "rho" => "ρ", "sigma" => "σ",
    "tau" => "τ", "phi" => "φ", "varphi" => "φ", "chi" => "χ", "psi" => "ψ",
    "omega" => "ω",
    "Gamma" => "Γ", "Delta" => "Δ", "Theta" => "Θ", "Lambda" => "Λ",
    "Xi" => "Ξ", "Pi" => "Π", "Sigma" => "Σ", "Phi" => "Φ", "Psi" => "Ψ",
    "Omega" => "Ω",
    "infty" => "∞",
)

"Comandos que viram `<mo>` (operador)."
const MATH_OPERADORES = Dict{String,String}(
    "cdot" => "·", "times" => "×", "div" => "÷", "pm" => "±", "mp" => "∓",
    "le" => "≤", "leq" => "≤", "ge" => "≥", "geq" => "≥", "ne" => "≠",
    "approx" => "≈", "equiv" => "≡", "propto" => "∝", "sim" => "∼",
    "to" => "→", "rightarrow" => "→", "leftarrow" => "←",
    "sum" => "Σ", "int" => "∫", "partial" => "∂",
)

"""
Funções: saem em `<mi>` **sem itálico**, que é a convenção tipográfica para nome de
função (`log`, `ln`, `sen`) — o itálico é para variável.
"""
const MATH_FUNCOES = Set([
    "log", "ln", "lg", "exp", "min", "max", "sen", "sin", "cos", "tan",
    "arcsen", "arcsin", "arccos", "arctan", "senh", "sinh", "cosh", "tanh",
    "abs",
])

"Delimitadores que `\\left` e `\\right` aceitam. `.` é o delimitador invisível."
const MATH_DELIMITADORES = Dict{String,String}(
    "(" => "(", ")" => ")", "[" => "[", "]" => "]",
    "{" => "{", "}" => "}", "|" => "|", "." => "",
)

"Operadores de um caractere aceitos soltos na fórmula."
const MATH_SINAIS = Dict{Char,String}(
    '+' => "+", '-' => "−", '=' => "=", '<' => "&lt;", '>' => "&gt;",
    '(' => "(", ')' => ")", '[' => "[", ']' => "]", '|' => "|",
    '/' => "/", ',' => ",", ';' => ";", '!' => "!", '·' => "·",
    # O asterisco marca a variante NÃO ADOTADA de uma equação (a Eq. 21* do separador):
    # é notação deste projeto, e o documento a imprime como a fonte a discute.
    '*' => "∗", ':' => ":", '%' => "%",
)

# ---------------------------------------------------------------------------
# O analisador léxico
# ---------------------------------------------------------------------------

"""
Um símbolo léxico da fórmula. `tipo` é um dos:
`:num`, `:ident`, `:sinal`, `:cmd`, `:abre`, `:fecha`, `:sub`, `:sup`.
"""
struct TokenTex
    tipo::Symbol
    valor::String
end

"""
    tokens_tex(tex) -> Vector{TokenTex}

Quebra a fórmula em símbolos léxicos. Caractere que não pertence ao subconjunto lança
`ArgumentError` aqui, antes de qualquer conversão — o erro aponta o caractere e a posição.
"""
function tokens_tex(tex::AbstractString)
    ts = TokenTex[]
    cs = collect(tex)
    i = 1
    n = length(cs)
    while i <= n
        c = cs[i]
        if isspace(c)
            i += 1
        elseif isdigit(c)
            # Número, com vírgula decimal e ponto de milhar quando entre dígitos — ver a
            # divergência (1). Os dígitos passam verbatim para `<mn>`: o separador é o
            # que a fonte escreveu, e não cabe a este arquivo reformatá-lo.
            j = i
            while j <= n && (isdigit(cs[j]) ||
                             ((cs[j] == ',' || cs[j] == '.') &&
                              j < n && isdigit(cs[j+1]) &&
                              j > i && isdigit(cs[j-1])))
                j += 1
            end
            push!(ts, TokenTex(:num, String(cs[i:j-1])))
            i = j
        elseif isletter(c)
            # Letras seguidas são um identificador só — ver a divergência (2).
            j = i
            while j <= n && isletter(cs[j])
                j += 1
            end
            push!(ts, TokenTex(:ident, String(cs[i:j-1])))
            i = j
        elseif c == '\\'
            i > n - 1 && throw(ArgumentError("barra invertida solta no fim de: $tex"))
            if isletter(cs[i+1])
                j = i + 1
                while j <= n && isletter(cs[j])
                    j += 1
                end
                push!(ts, TokenTex(:cmd, String(cs[i+1:j-1])))
                i = j
            else
                # `\{`, `\}`, `\|`, `\,` — o caractere escapado.
                push!(ts, TokenTex(:cmd, string(cs[i+1])))
                i += 2
            end
        elseif c == '{'
            push!(ts, TokenTex(:abre, "{")); i += 1
        elseif c == '}'
            push!(ts, TokenTex(:fecha, "}")); i += 1
        elseif c == '_'
            push!(ts, TokenTex(:sub, "_")); i += 1
        elseif c == '^'
            push!(ts, TokenTex(:sup, "^")); i += 1
        elseif haskey(MATH_SINAIS, c)
            push!(ts, TokenTex(:sinal, MATH_SINAIS[c])); i += 1
        else
            throw(ArgumentError(
                "caractere fora do subconjunto matemático: '$c' (posição $i) em: $tex"))
        end
    end
    return ts
end

# ---------------------------------------------------------------------------
# O analisador sintático
# ---------------------------------------------------------------------------

"Envolve num `<mrow>` só quando há mais de um filho — `<mrow>` de um filho é ruído."
_mrow(partes::Vector{String}) =
    length(partes) == 1 ? partes[1] : string("<mrow>", join(partes), "</mrow>")

"""
    _argumento(ts, i) -> (String, i)

Lê **um** argumento: ou um grupo `{…}` inteiro, ou o próximo átomo solto. É a regra do
LaTeX, e é o que faz `\\frac12` e `\\frac{a}{b}` funcionarem iguais.
"""
function _argumento(ts::Vector{TokenTex}, i::Int)
    i > length(ts) && throw(ArgumentError("faltou argumento no fim da fórmula"))
    if ts[i].tipo === :abre
        partes, j = _sequencia(ts, i + 1, :fecha)
        j > length(ts) && throw(ArgumentError("chave `{` sem fechamento"))
        return _mrow(partes), j + 1
    end
    return _atomo(ts, i)
end

"""
    _atomo(ts, i) -> (String, i)

Um átomo **sem** os scripts: número, identificador, sinal, comando ou grupo.
"""
function _atomo(ts::Vector{TokenTex}, i::Int)
    t = ts[i]
    if t.tipo === :num
        return string("<mn>", t.valor, "</mn>"), i + 1
    elseif t.tipo === :ident
        return string("<mi>", t.valor, "</mi>"), i + 1
    elseif t.tipo === :sinal
        return string("<mo>", t.valor, "</mo>"), i + 1
    elseif t.tipo === :abre
        partes, j = _sequencia(ts, i + 1, :fecha)
        j > length(ts) && throw(ArgumentError("chave `{` sem fechamento"))
        return _mrow(partes), j + 1
    elseif t.tipo === :cmd
        return _comando(ts, i)
    elseif t.tipo === :fecha
        throw(ArgumentError("chave `}` sem abertura"))
    end
    throw(ArgumentError("símbolo inesperado na fórmula: $(t.tipo) $(t.valor)"))
end

"""
    _comando(ts, i) -> (String, i)

Resolve um `\\comando`. O `else` final é a guarda que sustenta a regra deste arquivo:
comando desconhecido **lança**, em vez de sair como texto ou sumir.
"""
function _comando(ts::Vector{TokenTex}, i::Int)
    nome = ts[i].valor
    if nome == "frac" || nome == "dfrac" || nome == "tfrac"
        num, j = _argumento(ts, i + 1)
        den, k = _argumento(ts, j)
        return string("<mfrac>", num, den, "</mfrac>"), k
    elseif nome == "sqrt"
        # `\sqrt[n]{x}` — o índice opcional entre colchetes.
        j = i + 1
        if j <= length(ts) && ts[j].tipo === :sinal && ts[j].valor == "["
            idx, k = _sequencia(ts, j + 1, :sinal, "]")
            radicando, m = _argumento(ts, k + 1)
            return string("<mroot>", radicando, _mrow(idx), "</mroot>"), m
        end
        radicando, k = _argumento(ts, j)
        return string("<msqrt>", radicando, "</msqrt>"), k
    elseif nome == "text" || nome == "mathrm" || nome == "operatorname"
        texto, j = _texto_literal(ts, i + 1)
        etiqueta = nome == "text" ? "mtext" : "mi"
        atributo = nome == "text" ? "" : " mathvariant=\"normal\""
        return string("<", etiqueta, atributo, ">", texto, "</", etiqueta, ">"), j
    elseif nome == "left"
        return _cerca(ts, i)
    elseif nome == "right"
        throw(ArgumentError("`\\right` sem `\\left` correspondente"))
    elseif haskey(MATH_SIMBOLOS, nome)
        return string("<mi>", MATH_SIMBOLOS[nome], "</mi>"), i + 1
    elseif haskey(MATH_OPERADORES, nome)
        return string("<mo>", MATH_OPERADORES[nome], "</mo>"), i + 1
    elseif nome in MATH_FUNCOES
        return string("<mi mathvariant=\"normal\">", nome, "</mi>"), i + 1
    elseif haskey(MATH_DELIMITADORES, nome)
        return string("<mo>", MATH_DELIMITADORES[nome], "</mo>"), i + 1
    elseif nome == ","
        # `\,` — o espaço fino do LaTeX.
        return "<mspace width=\"0.17em\"/>", i + 1
    elseif nome == "prime"
        # A linha da resistência de incrustação por unidade de área (R″) — Saari a
        # escreve assim, e o documento a reproduz.
        return "<mo>′</mo>", i + 1
    elseif nome == "dot"
        # Vazão mássica: o ponto sobre o símbolo é o que distingue ṁ de m.
        base, j = _argumento(ts, i + 1)
        return string("<mover>", base, "<mo>˙</mo></mover>"), j
    elseif nome == "bar" || nome == "overline"
        base, j = _argumento(ts, i + 1)
        return string("<mover>", base, "<mo>‾</mo></mover>"), j
    elseif nome == "quad"
        return "<mspace width=\"1em\"/>", i + 1
    elseif nome == "qquad"
        return "<mspace width=\"2em\"/>", i + 1
    end
    throw(ArgumentError("comando fora do subconjunto matemático: \\$nome"))
end

"""
    _cerca(ts, i) -> (String, i)

`\\left⟨d⟩ … \\right⟨d⟩`: os delimitadores saem `stretchy`, que é o ponto — é o que faz o
colchete crescer para cobrir a fração que ele abraça.
"""
function _cerca(ts::Vector{TokenTex}, i::Int)
    abre, j = _delimitador(ts, i + 1)
    partes, k = _sequencia(ts, j, :cmd, "right")
    k > length(ts) && throw(ArgumentError("`\\left` sem `\\right` correspondente"))
    fecha, m = _delimitador(ts, k + 1)
    pedacos = String[]
    isempty(abre) || push!(pedacos, "<mo stretchy=\"true\">$abre</mo>")
    append!(pedacos, partes)
    isempty(fecha) || push!(pedacos, "<mo stretchy=\"true\">$fecha</mo>")
    return string("<mrow>", join(pedacos), "</mrow>"), m
end

"Lê o delimitador que segue um `\\left` ou um `\\right`."
function _delimitador(ts::Vector{TokenTex}, i::Int)
    i > length(ts) && throw(ArgumentError("faltou o delimitador de `\\left`/`\\right`"))
    t = ts[i]
    bruto = t.tipo === :cmd ? t.valor :
            t.tipo === :sinal ? _sinal_cru(t.valor) :
            throw(ArgumentError("delimitador inválido: $(t.valor)"))
    haskey(MATH_DELIMITADORES, bruto) ||
        throw(ArgumentError("delimitador fora do subconjunto: $bruto"))
    return MATH_DELIMITADORES[bruto], i + 1
end

"Desfaz o mapeamento de `MATH_SINAIS` para reconhecer o delimitador pelo caractere."
_sinal_cru(v::AbstractString) = v == "&lt;" ? "<" : v == "&gt;" ? ">" : v

"""
    _texto_literal(ts, i) -> (String, i)

O conteúdo de `\\text{…}` / `\\mathrm{…}`: palavras, sem interpretação matemática.
"""
function _texto_literal(ts::Vector{TokenTex}, i::Int)
    (i > length(ts) || ts[i].tipo !== :abre) &&
        throw(ArgumentError("`\\text`/`\\mathrm` exige `{…}`"))
    pedacos = String[]
    j = i + 1
    while j <= length(ts) && ts[j].tipo !== :fecha
        push!(pedacos, ts[j].valor)
        j += 1
    end
    j > length(ts) && throw(ArgumentError("`\\text`/`\\mathrm` sem fechamento"))
    return join(pedacos, " "), j + 1
end

"""
    _sequencia(ts, i, tipo_parada, valor_parada) -> (Vector{String}, i)

Lê átomos **com** seus scripts até o símbolo de parada (que NÃO é consumido), ou até o
fim. É onde `_` e `^` se resolvem: `V_t^2` vira um `<msubsup>` só, e não dois elementos.
"""
function _sequencia(ts::Vector{TokenTex}, i::Int, tipo_parada::Symbol,
                    valor_parada::Union{Nothing,String} = nothing)
    partes = String[]
    while i <= length(ts)
        t = ts[i]
        if t.tipo === tipo_parada &&
           (valor_parada === nothing || t.valor == valor_parada)
            return partes, i
        end
        base, i = _atomo(ts, i)
        sub = nothing
        sup = nothing
        # Aceita as duas ordens (`x_a^b` e `x^b_a`), como o LaTeX.
        while i <= length(ts) && (ts[i].tipo === :sub || ts[i].tipo === :sup)
            marca = ts[i].tipo
            arg, i = _argumento(ts, i + 1)
            if marca === :sub
                sub === nothing || throw(ArgumentError("dois subscritos no mesmo átomo"))
                sub = arg
            else
                sup === nothing || throw(ArgumentError("dois expoentes no mesmo átomo"))
                sup = arg
            end
        end
        if sub !== nothing && sup !== nothing
            push!(partes, string("<msubsup>", base, sub, sup, "</msubsup>"))
        elseif sub !== nothing
            push!(partes, string("<msub>", base, sub, "</msub>"))
        elseif sup !== nothing
            push!(partes, string("<msup>", base, sup, "</msup>"))
        else
            push!(partes, base)
        end
    end
    return partes, i
end

# ---------------------------------------------------------------------------
# A porta de entrada
# ---------------------------------------------------------------------------

"""
    mathml(tex; display = true) -> String

Converte o subconjunto LaTeX descrito no cabeçalho deste arquivo em MathML.

`display = true` produz `display="block"`, que é o da faixa de equação da folha 03 —
frações empilhadas em tamanho cheio. `display = false` é o da lista `ONDE:`, onde o
símbolo corre dentro da linha de texto.

Lança `ArgumentError` em qualquer comando ou caractere fora do subconjunto. É deliberado:
uma equação que falhasse em silêncio viraria uma faixa vazia num documento assinado.
"""
function mathml(tex::AbstractString; display::Bool = true)
    isempty(strip(tex)) && throw(ArgumentError("fórmula vazia"))
    ts = tokens_tex(tex)
    # Sem símbolo de parada: `:nunca` não é tipo de token nenhum, então a sequência só
    # termina no fim. Um `}` sobrando cai em `_atomo`, que o nomeia.
    partes, _ = _sequencia(ts, 1, :nunca)
    atributo = display ? " display=\"block\"" : ""
    return string("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"", atributo, ">",
                  join(partes), "</math>")
end
