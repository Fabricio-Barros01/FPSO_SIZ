"""
A camada **documental** de um método: quais equações ele usa, como elas se escrevem em
notação matemática, o que cada variável significa, o que se assume e o que se verifica.

É o par de [`trace_blocks`](@ref) e [`result_fields`](@ref), e existe pelo mesmo motivo
que eles: quem sabe que o separador trifásico resolve a Eq. 14 de Alves & Komesu é o
**método**, não a tela. O rastro de cálculo (`CalcTrace`) já diz *quanto deu*; o que
faltava é *o que estava sendo resolvido* — a equação por extenso, a definição das
variáveis, a referência e a faixa de validade. Sem isso o memorial exportado é uma lista
de números com um rótulo curto ao lado, e quem assina não tem como conferir.

# A regra que sustenta tudo: aqui não entra número calculado

Nenhum tipo deste arquivo tem campo numérico. Isso não é estilo, é a garantia:

* o memorial **não pode** mostrar um valor que o motor não calculou, porque não há onde
  guardá-lo — todo número do documento vem de um [`TraceEntry`](@ref) ou de um
  [`ResultField`](@ref), que são o cálculo que de fato correu;
* o memorial **não pode** discordar da tela, porque os dois leem a mesma estrutura;
* e não nasce uma segunda matemática em `app/`, que é o defeito que este projeto evita
  desde que a formatação PT-BR passou a existir uma vez só.

Os coeficientes que aparecem dentro de `notacao` (o `34,5` da Eq. 14, o `0,033` da
Eq. 17) **não** são exceção à regra: eles são parte da equação, não resultado dela — a
mesma distinção que faz `config/equipment/*/`*`.toml`* guardar constante de correlação e
não guardar resposta.

# A rastreabilidade que o documento promete

    entrada          ParameterSpec + o valor do caso          (folha 02)
      ↓
    variável         VariavelDoc — símbolo, o que é, unidade  (folha 03)
      ↓
    equação          EquacaoDoc.numero ≡ TraceEntry.eq        (folha 03)
      ↓
    intermediário    TraceEntry.value                         (folha 03)
      ↓
    final            ResultField.value                        (folha 04)
      ↓
    verificação      ResultField.status + VerificacaoDoc      (folha 04)

Os dois `≡` do meio são o que `test/memorial.jl` verifica, e são o elo frágil: uma
equação documentada que o motor não resolve é decoração, e um número no rastro que a
folha 03 não explica é um número órfão no documento que vai assinado.
"""

# ---------------------------------------------------------------------------
# Os descritores documentais
# ---------------------------------------------------------------------------

"""
Uma premissa de projeto — o que se assumiu antes de calcular, e de onde veio.

`referencia` não é enfeite: uma premissa sem fonte é opinião, e a folha 02 do memorial
reserva uma coluna para ela justamente porque quem revisa confere premissa por premissa.
"""
struct PremissaDoc
    item::String          # "P1"
    texto::String
    referencia::String
end

"Uma variável da equação: o símbolo como ele aparece na notação, o que é e em quê."
struct VariavelDoc
    simbolo::String
    descricao::String
    unidade::String
end

"""
Uma equação do método, como o memorial a imprime.

`numero` é a **chave de rastreabilidade**: tem de ser exatamente a mesma string que o
método carimba em `TraceEntry.eq` ao resolver esta equação. É por esse par que a folha 03
(a equação) e a folha 04 (o resultado) se amarram, e é ele que `test/memorial.jl`
verifica nos dois sentidos.

`notacao` é a equação **por extenso**, em notação matemática — nunca em sintaxe de
código. É o que o revisor lê para decidir se a conta certa foi feita.

`tex` é a **mesma** equação num subconjunto de LaTeX, e é dela que sai a simbologia
impressa: a folha 03 a converte em MathML (ver `mathml` em `app/src/memorial/mathml.jl`),
que é o que produz fração empilhada, radical cobrindo o radicando e expoente sobrescrito
de verdade.

As duas convivem porque respondem a meios diferentes, e nenhuma substitui a outra:
`notacao` é uma linha de texto, e é o que o `.txt` exportado grava e o painel da tela
mostra, onde não há como desenhar fração; `tex` só existe onde há tipografia. Manter as
duas custa escrevê-las juntas — e é por isso que `test/memorial.jl` exige as duas em toda
equação, e que o conversor lança em símbolo desconhecido em vez de imprimir faixa vazia.

`validade` é a condição sob a qual a correlação vale (faixa de Reynolds, tamanho de
gotícula, geometria). Vazio significa "a fonte não declara nenhuma", e é uma resposta
honesta; um palpite não é.
"""
struct EquacaoDoc
    numero::String                  # "Eq. 14" — casa com TraceEntry.eq
    grandeza::String                # o que esta equação calcula
    notacao::String                 # a equação por extenso, em texto
    tex::String                     # a mesma equação, em LaTeX → MathML
    variaveis::Vector{VariavelDoc}
    referencia::String
    validade::String
end

"""
`tex` é **posicional**, logo depois de `notacao`, e não um `referencia = …` opcional. É
de propósito: uma equação nova não tem como nascer sem simbologia, porque o construtor
não a aceita sem. A alternativa — argumento nomeado com default vazio mais um teste que
o exige — deixa a folha 03 sair com faixa vazia entre escrever a equação e rodar a
suíte, e é o tipo de janela que o resto deste arquivo fecha no tipo.
"""
EquacaoDoc(numero, grandeza, notacao, tex, variaveis; referencia = "", validade = "") =
    EquacaoDoc(String(numero), String(grandeza), String(notacao), String(tex),
               collect(VariavelDoc, variaveis), String(referencia), String(validade))

"""
Um resultado do dimensionamento, e **de qual equação ele saiu**.

`rotulo` casa com o `label` de um [`ResultField`](@ref) — é assim que o valor chega ao
documento sem que este arquivo o conheça. `equacao` é o número (ou os números, separados
por `" / "`) da folha 03 que o produziram: é a coluna "EQUAÇÃO" da folha 04, o elo que
liga cada número da conclusão à conta que o gerou.

Dois números quando a regra depende do bloco que governa — o `Lss` de um vaso sai da
Eq. 15 quando o gás governa e da Eq. 23 quando o líquido governa, e dizer só uma das duas
mandaria o revisor conferir a errada em metade dos casos.
"""
struct ResultadoDoc
    rotulo::String        # ≡ ResultField.label
    simbolo::String
    equacao::String       # "Eq. 22" | "Eq. 15 / Eq. 23"
end

"""
Uma verificação de projeto: o critério que o resultado tem de atender para o
equipamento ser aceito.

`campo` é o `label` do [`ResultField`](@ref) que carrega o valor **e o `status`**. O
`ATENDE` / `NÃO ATENDE` da folha 04 sai desse `status`, e de nada mais: escrever o
veredito aqui seria escrever no documento uma aprovação que ninguém calculou. Um campo
com `status = :neutro` não tem veredito a dar, e o documento imprime travessão em vez de
inventar um.

`criterio` é o limite **em texto** ("3 ≤ SR ≤ 5", "d ≤ teto de decantação"): a banda em
si é parâmetro do usuário e chega ao documento pelo valor, não por este campo.
"""
struct VerificacaoDoc
    descricao::String
    campo::String         # ≡ ResultField.label
    criterio::String
    unidade::String
end

"""
O memorial de um método: tudo o que o documento diz e que não é número.

`sigla`, `equipamento` e `titulo` são o que a tabela de módulos do handoff de design
chama de personalização por equipamento — a sigla entra no número do documento
(`MC-SENAI-<sigla>-ENG-<seq>-<rev>`) e o título, no bloco de título de todas as folhas.

`hipoteses` é obrigatória na folha 02 do handoff, e é onde as divergências conhecidas em
relação à fonte publicada aparecem para quem assina. Num método que reproduz um artigo
com erratas — e o separador trifásico é um — esconder isso no comentário do código seria
publicar a conta sem a ressalva.

`natureza` diz **que tipo de documento é este**, e existe porque nem todo módulo do
programa dimensiona um equipamento:

* `:dimensionamento` (o default) — o documento descreve um equipamento a construir. A
  seção de resultados se chama "RESULTADOS DO DIMENSIONAMENTO";
* `:metas` — o documento descreve **alvos de um processo**, não um equipamento. É o caso
  da Análise Pinch, que devolve a utilidade quente e a fria mínimas de uma REDE de
  correntes e a temperatura de pinch: não há casco, não há diâmetro, e chamar a seção de
  "resultados do dimensionamento" prometeria um equipamento que ninguém dimensionou.

`verificacoes` **pode ser vazia**, e a seção some do documento quando é. A regra é a
mesma que vale para cada linha: uma VERIFICAÇÃO existe quando o motor de fato emite um
veredito, e não existe quando não emite. Um módulo que só calcule metas pode
legitimamente não ter nenhuma — o que não pode é imprimir a seção com travessões, que se
lê como conferência feita.
"""
struct MemorialSpec
    sigla::String                       # "SEP"
    equipamento::String                 # "SEPARADOR TRIFÁSICO"
    titulo::String                      # "DIMENSIONAMENTO DE SEPARADOR TRIFÁSICO"
    natureza::Symbol                    # :dimensionamento | :metas
    premissas::Vector{PremissaDoc}
    hipoteses::Vector{String}
    equacoes::Vector{EquacaoDoc}
    resultados::Vector{ResultadoDoc}
    verificacoes::Vector{VerificacaoDoc}
    conclusao::String
end

MemorialSpec(; sigla, equipamento, titulo, natureza::Symbol = :dimensionamento,
               premissas = PremissaDoc[],
               hipoteses = String[], equacoes = EquacaoDoc[],
               resultados = ResultadoDoc[], verificacoes = VerificacaoDoc[],
               conclusao = "") =
    MemorialSpec(String(sigla), String(equipamento), String(titulo), natureza,
                 collect(PremissaDoc, premissas), collect(String, hipoteses),
                 collect(EquacaoDoc, equacoes), collect(ResultadoDoc, resultados),
                 collect(VerificacaoDoc, verificacoes), String(conclusao))

"""
    titulo_resultados(spec) -> String

Como se chama a seção de resultados deste documento — ver `natureza` em
[`MemorialSpec`](@ref).
"""
titulo_resultados(s::MemorialSpec) =
    s.natureza === :metas ? "METAS DE ENERGIA DA REDE" : "RESULTADOS DO DIMENSIONAMENTO"

"""
    titulo_resumo(spec) -> String

Como se chama o resumo da folha de rosto. Um documento de metas não resume um
"dimensionamento" — resume as metas que calculou.
"""
titulo_resumo(s::MemorialSpec) =
    s.natureza === :metas ? "RESUMO DAS METAS" : "RESUMO DO DIMENSIONAMENTO"

# ---------------------------------------------------------------------------
# O hook
# ---------------------------------------------------------------------------

"""
    memorial_spec(m) -> MemorialSpec | nothing

A camada documental deste método, ou `nothing` quando ele ainda não declarou nenhuma.

`nothing` é o default **de propósito**, e não um `MemorialSpec` vazio. Um spec vazio
produziria um documento de quatro folhas com o bloco de título correto, o carimbo do
SENAI, o quadro de revisões — e nenhuma equação, nenhuma premissa e nenhuma verificação:
um documento de aparência oficial e conteúdo nenhum, que é exatamente o artefato que não
pode existir num projeto onde o memorial vai anexo ao relatório. Com `nothing` a
interface não oferece o botão, que é a resposta honesta para "este método ainda não tem
memorial".

Quem a implementa é o método, no seu próprio arquivo ou em `src/memorial_specs/`.
"""
memorial_spec(::AbstractSizingMethod) = nothing

"""
    tem_memorial(m) -> Bool

Se este método declara memorial documental. É o que a tela consulta para decidir se
mostra o botão — ver [`memorial_spec`](@ref).
"""
tem_memorial(m::AbstractSizingMethod) = memorial_spec(m) !== nothing

# ---------------------------------------------------------------------------
# Consultas — usadas pelo renderizador e pelos testes
# ---------------------------------------------------------------------------

"""
Marcador de "não é uma equação" no rastro.

`trace_selection!` carimba `"—"` na linha que registra **qual diâmetro foi escolhido**:
é uma decisão de projeto (o menor `|SR − alvo|` dentro da banda), não uma equação da
fonte. A folha 03 não tem o que imprimir para ela, e a bijeção equação↔rastro a ignora
dos dois lados.
"""
const SEM_EQUACAO = "—"

"""
    equacoes_do_rastro(tr) -> Vector{String}

As equações que o motor de fato resolveu, na ordem em que apareceram e sem repetição.
Descarta o marcador [`SEM_EQUACAO`](@ref).

É o lado "cálculo" da bijeção que `test/memorial.jl` verifica contra
[`memorial_spec`](@ref).
"""
function equacoes_do_rastro(tr::CalcTrace)
    vistas = String[]
    for e in tr.entries
        e.eq == SEM_EQUACAO && continue
        e.eq in vistas || push!(vistas, e.eq)
    end
    return vistas
end

"""
    equacoes_citadas(spec) -> Vector{String}

Os números de equação que os resultados da folha 04 citam na coluna "EQUAÇÃO".

Separa por `" / "` porque um resultado pode sair de uma entre duas regras — ver
[`ResultadoDoc`](@ref). Compara-se por igualdade exata depois de separar, e não por
`occursin`: `"Eq. 21"` é prefixo de `"Eq. 21*"` e `"Eq. 1"` é prefixo de `"Eq. 14"`, e
uma verificação por substring aprovaria a citação errada.
"""
function equacoes_citadas(spec::MemorialSpec)
    out = String[]
    for r in spec.resultados, n in split(r.equacao, " / ")
        n = strip(String(n))
        (isempty(n) || n == SEM_EQUACAO) && continue
        n in out || push!(out, n)
    end
    return out
end

"""
    entradas_do_rastro(tr, numero) -> Vector{TraceEntry}

As linhas do rastro que resolveram esta equação — de onde a folha 03 tira o valor
calculado de cada bloco. Vazio quando o método não a resolveu neste caso (uma equação
pode ser pulada: a variante geométrica da Eq. 21 some quando não há água livre).
"""
entradas_do_rastro(tr::CalcTrace, numero::AbstractString) =
    filter(e -> e.eq == numero, tr.entries)
