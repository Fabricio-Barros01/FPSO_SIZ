# Passo 8 — Memorial de cálculo documental (três vasos: SEP, VKO, TRE)

**Módulo:** `memorial` · **Não é um método de dimensionamento** — é a camada documental
do contrato método↔motor.
**Fonte do documento:** handoff de design
`References/design_handoff_memorial_calculo/` (README + protótipo `.dc.html` +
`referencia/MC-SENAI-SEP-ENG-001-0.xlsx`).
**Fonte da física documentada:** Alves & Komesu (2025), Lajer v.12 n.1 p.16-29, sobre
Stewart & Arnold (2008) — a mesma do [passo 4](04-separador-trifasico.md).
**Arquivos:** [memorial.jl](../../src/memorial.jl),
[memorial_specs/](../../src/memorial_specs/) (um por método),
[app/src/memorial/documento.jl](../../app/src/memorial/documento.jl),
[app/src/memorial/folhas.jl](../../app/src/memorial/folhas.jl),
[app/public/memorial.css](../../app/public/memorial.css),
[test/memorial.jl](../../test/memorial.jl).

Até aqui o programa exportava um memorial: um `.txt` com o rastro de cálculo em colunas
de largura fixa. Ele é honesto e é **insuficiente** — traz os números e não traz a conta.
Quem recebe o arquivo lê `settling  Eq. 17     (h_o)max  1130,30000  mm` e não tem como
saber qual é a Eq. 17, de onde ela vem, o que `(h_o)max` significa nem sob que hipótese
ela vale. Este passo acrescenta a camada que faltava, **sem duplicar nenhuma física**.

---

## 1. O que foi acrescentado, e onde

| camada | o que declara | arquivo |
|---|---|---|
| Contrato | `MemorialSpec`, `EquacaoDoc`, `VariavelDoc`, `PremissaDoc`, `ResultadoDoc`, `VerificacaoDoc` | `src/memorial.jl` |
| Conteúdo, por equipamento | SEP 18 eqs · VKO 9 · TRE 11, cada um com premissas, hipóteses, resultados e verificações próprios | `src/memorial_specs/*.jl` |
| Infra documental | folha A4, bloco de título, quadro de revisões, grade de 28 colunas, tokens, paginação | `app/src/memorial/documento.jl` |
| Folhas | rosto, premissas, fórmulas, resultados, figuras | `app/src/memorial/folhas.jl` |
| Impressão | geometria A4 e tipografia do handoff | `app/public/memorial.css` |
| Rota | `GET /app/:box/memorial` → documento HTML imprimível | `app/src/server.jl` |

Nenhuma dependência nova. O `MemorialSpec` é puro dado/texto e o documento é HTML +
CSS: a geração do PDF é a impressão do navegador, que é o que o projeto já decidiu ao
trocar PNG por SVG (não há rasterizador no programa).

---

## 2. A regra dura: a camada documental não guarda número

Nenhum tipo de `src/memorial.jl` tem campo numérico — todos são `String` ou vetores de
`String`/descritores. **Não existe onde escrever um valor calculado.** Em consequência:

* todo número do documento vem de um `TraceEntry` (o rastro) ou de um `ResultField` (os
  campos que o método declara), que são o cálculo que de fato correu;
* o documento não pode discordar da tela;
* não nasce uma segunda matemática em `app/`.

`test/memorial.jl` verifica isso sobre os `fieldtypes` dos seis tipos — é guarda
estrutural, não disciplina.

Os coeficientes dentro da notação (`34,5` na Eq. 14, `0,033` na Eq. 17) **não** são
exceção: são parte da equação, não resultado dela. É a mesma distinção que faz
`config/equipment/*/*.toml` guardar constante de correlação e não guardar resposta.

---

## 3. Rastreabilidade: o caminho que o documento percorre

```
entrada          ParameterSpec + valor do canto governante        folha 02
  ↓
variável         VariavelDoc — símbolo, descrição, unidade        folha 03
  ↓
equação          EquacaoDoc.numero ≡ TraceEntry.eq                folha 03
  ↓
intermediário    TraceEntry.value  (linha "VALOR CALCULADO")      folha 03
  ↓
final            ResultField.value                                folha 04
  ↓
verificação      ResultField.status + VerificacaoDoc.criterio     folha 04
```

Os dois `≡` do meio são o elo frágil, e são testados nos **dois sentidos**:

| guarda | o que ela impede |
|---|---|
| toda `TraceEntry.eq` tem `EquacaoDoc` | número órfão no documento assinado |
| toda `EquacaoDoc` está no rastro **ou** é citada por um `ResultadoDoc` | equação decorativa que ninguém resolve |
| todo `ResultadoDoc.rotulo` casa com um `ResultField.label` | linha da folha 04 que sai em travessão |
| todo `VerificacaoDoc.campo` casa com um `ResultField.label` | verificação sem veredito calculado |

A coluna `EQUAÇÃO` da folha 04 é o elo visível: ela amarra cada resultado ao bloco da
folha 03 que o produziu.

---

## 4. As 18 equações documentadas

Na ordem do cálculo — a mesma em que `sizing_constraints` as resolve, não a numérica.

| # | bloco | equação | grandeza | no rastro |
|---|---|---|---|---|
| 1 | A | Eq. 9–11 | coeficiente de arrasto `C_D` | sim |
| 2 | A | Eq. 11 | velocidade terminal `V_t` | sim |
| 3 | A | Eq. 10 | Reynolds da gotícula | sim |
| 4 | A | Eq. 13 | constante de Souders–Brown `K` | sim |
| 5 | A | Eq. 14 | capacidade de gás — `d·Leff` | sim |
| 6 | B | Eq. 16 | `ΔSG` | sim |
| 7 | B | Eq. 17 | `(h_o)max` | sim |
| 8 | B | Eq. 20 | `(h_w)max` | sim |
| 9 | B | Eq. 18 | `Aw/A` | sim |
| 10 | B | Fig. 3 | coeficiente `β` | sim |
| 11 | B | Eq. 19 | teto por água em óleo | sim |
| 12 | B | Eq. 21 | teto por óleo em água (forma publicada) | sim |
| 13 | B | Eq. 21\* | variante geométrica — **não adotada** | sim |
| 14 | C | Eq. 22 | capacidade de líquido — `d²·Leff` | sim |
| 15 | — | Eq. 15 | `Lss` quando o gás governa | citada |
| 16 | — | Eq. 23 | `Lss` quando o líquido governa | citada |
| 17 | — | Eq. 24 | esbeltez `SR` | sim |
| 18 | — | Geom. | volume do casco entre costuras | citada |

**`Geom.` não é numerada como equação do artigo de propósito.** O volume é cilindro reto
sobre `Lss` e não consta da fonte; chamá-la de "Eq. 25" mandaria o revisor procurar na
referência uma equação que ela não tem. A célula de referência diz, literalmente,
*"Geometria do cilindro reto — não consta da fonte"*.

O marcador `"—"` que `trace_selection!` carimba na linha do diâmetro escolhido fica
**fora** da bijeção nos dois sentidos: é decisão de projeto (menor `|SR − alvo|` dentro
da banda), não equação da fonte.

---

## 5. As quatro hipóteses, agora no documento e não no comentário

As divergências em relação ao texto publicado estavam documentadas no cabeçalho de
`src/sizing/separator/stewart_arnold.jl` — isto é, para quem lê o código. O memorial é
o que vai anexo ao relatório, e agora elas estão na folha 02:

| # | o que diverge | decisão |
|---|---|---|
| H1 | Eq. 22 — o artigo imprime `4,12×10⁴`, inconsistente com a própria Tabela 3 | adotado o coeficiente derivado de S&A (0,35 % contra 1,9 %) |
| H2 | Tabela 1 — os `0,6 cP` de viscosidade do gás são de líquido (colunas trocadas) | `µ_g` exposto como entrada explícita |
| H3 | Eq. 21 — o artigo divide `(h_w)max` por `β`, que é a cota do **óleo** | **segue-se o publicado**; a variante geométrica sai como Eq. 21\* |
| H4 | Eq. 15/23 — S&A mandam o **maior** entre as duas folgas; o artigo usa a do bloco governante | segue-se o artigo |

A H3 é a que mais custa e está escrita no documento com o número: sob a leitura
geométrica o teto cairia de 16508 para 3810 mm e o mecanismo governante se inverteria —
ou seja, **o método publicado é não-conservador nesse ponto**. Um memorial que omitisse
isso publicaria a conta sem a ressalva.

---

## 6. Fidelidade ao handoff — o que se reproduz e o que não

O handoff descreve como reproduzir a referência **numa planilha** (XLSX). A decisão deste
projeto é HTML → impressão do navegador → PDF, e aí não há planilha para escalar.

**Reproduzido:**

* grade de **28 colunas** `A…AB` com as larguras exatas em caracteres (soma 118,71) —
  é ela que põe cada campo e cada coluna de tabela na banda da referência
  (`A:J` parâmetro, `K:N` símbolo, `O:S` valor, `T:V` unidade, `W:AB` fonte/equação);
* A4 retrato, margens 0,7 / 0,3 / 0,4 / 0,4 pol; **uma folha = uma página**;
* bloco de título (linhas 1–8) em **todas** as folhas, escrito por uma função só;
* quadro de revisões (linhas 73–79) **só** na folha de rosto; nota de propriedade em todas;
* tipografia: Arial em tudo, Times New Roman itálico nas equações, e os corpos tabelados
  (5 / 7 / 7,5 / 8,5 / 9 / 11 pt);
* bordas `medium` no contorno e nas divisões estruturais, `thin` nas grades de tabela,
  sem preenchimento de fundo colorido;
* número do documento `MC-SENAI-SEP-ENG-001-0` e título
  `MEMÓRIA DE CÁLCULO – DIMENSIONAMENTO DE SEPARADOR TRIFÁSICO`;
* **token não resolvido é erro de emissão**, nunca célula vazia;
* regra de paginação: bloco nunca partido, folha nova com o bloco de título repetido e
  `(cont.)` no título da seção.

**Não reproduzido, e por quê:**

| item | motivo |
|---|---|
| escala global de 69 % / 66 % | é o `fitToHeight` de uma planilha; em HTML os corpos tabelados são os tamanhos impressos diretos, e aplicar 69 % sobre eles daria 6,2 pt |
| "quatro folhas" | são **quatro tipos** de folha; o separador tem 18 equações e a regra de paginação do próprio handoff abre folhas de fórmulas adicionais — são 12 no caso de referência |
| os corpos de 11 pt do bloco de título | pressupõem o escalonamento global da planilha; em A4 sem escala não cabem na banda. Ver o defeito 1 em §11.2 |
| XLSX como artefato final | decisão de projeto: HTML→PDF reaproveita as figuras SVG e não exige rasterizador nem dependência nova |

A grade de 28 colunas existe **duas vezes** (em `COLUNAS`, no Julia, e no
`grid-template-columns` do CSS). `app/smoke.jl` compara as duas listas, pela mesma razão
que já comparava a paleta de cores.

---

## 7. Consistência tela ↔ documento

Não é verificada por comparação: é **estrutural**. O cartão da tela e a folha de
resultados chamam a mesma função.

```
cartao(st)            ─┐
                       ├─► campos_resultado(st) ─► FPSOSiz.result_fields(metodo, alvo_cartao(st))
folha_resultados(...) ─┘
```

`alvo_cartao` é o ponto do **cursor**, não o ótimo da varredura. É deliberado: quem
arrasta o cursor e manda imprimir recebe o documento do vaso que está vendo. Se o
documento apontasse sempre para o ótimo, a tela mostraria um vaso e o PDF ao lado mostraria
outro — com o mesmo número de documento e a mesma assinatura.

O smoke test fecha isso também pelo texto: o valor formatado que a rota `/api/:box/estado`
devolve no cartão tem de aparecer como conteúdo de célula no HTML do documento.

---

## 8. O que o documento mostra que a tela não mostra

| folha | conteúdo que só existe aqui |
|---|---|
| 02 | as 6 premissas com referência; as 4 hipóteses/limitações; a `note` de proveniência de cada entrada |
| 03 | a equação por extenso, a definição de cada variável com unidade, a referência e a **faixa de validade** |
| 04 | a coluna `EQUAÇÃO` ligando cada resultado à conta; o critério textual de cada verificação |

E o que a tela mostra e o documento repete sem recalcular: o resumo na folha de rosto, os
valores da folha 04 e as figuras (elevação, seção transversal e os dois gráficos de
varredura — as mesmas SVG, vetoriais, que imprimem na resolução da impressora).

---

## 9. Verificação

```sh
julia --project=.   test/runtests.jl memorial     # contrato + bijeção equação↔rastro
julia --project=app app/smoke.jl                  # rota, 4 tipos de folha, tela↔documento
```

Manual, com o servidor no ar:

1. abrir **Separador trifásico**, abrir `exemplo_alves_komesu.toml`, **Dimensionar**;
2. clicar em **📄 Memorial** — abre noutra aba;
3. conferir: bloco de título em todas as folhas, quadro de revisões só na primeira,
   `folha X de Y` coerente, nenhum `{{token}}` visível;
4. **Ctrl+P → Salvar como PDF**: uma folha por página, sem página em branco entre elas;
5. comparar os valores da folha 04 com o cartão da tela — têm de ser idênticos.

O caso-ouro do separador (`d = 6300 mm`, `Leff = 18,59 m`, `Lss = 24,78 m`, `SR = 3,93`
no exemplo do app) atravessa engine → tela → documento com os mesmos valores.

---

## 10. Lacunas declaradas

| # | lacuna | consequência | encaminhamento |
|---|---|---|---|
| 1 | **Três dos seis métodos têm `memorial_spec`** — os três vasos. Bomba, trocador e pinch devolvem `nothing` | o botão Memorial não aparece neles — não há documento vazio | ver §12 |
| 2 | Cliente, unidade e executor saem como `A DEFINIR` por padrão | preenchem-se pela consulta (abaixo) ou à mão no PDF | um formulário de metadados do estudo |
| 3 | O quadro de revisões só registra a emissão inicial | revisões seguintes não são rastreadas pelo programa | exigiria persistir histórico de revisão por estudo |
| ~~4~~ | ~~`meta_da_consulta` lê os parâmetros de forma defensiva e a chave do Genie não foi confirmada~~ | **fechada** — verificada e fixada por teste, ver abaixo | — |
| 5 | O documento é do **caso governante**; os demais cantos não aparecem | o `.txt` exportado continua trazendo o rastro de todos | manter os dois artefatos, que respondem a perguntas diferentes |
| ~~6~~ | ~~Não há visor 3D nem design system "Industry"~~ | **fechada** — [passo 9](09-ui-industry-3d.md) | — |
| ~~7~~ | ~~A verificação do teto de decantação sai em `—`~~ | **fechada** — ver §10.1 | — |
| ~~8~~ | ~~Eq. 15 e Eq. 23 sem `VALOR CALCULADO`~~ | **fechada** — ver §10.2 | — |

### 10.0 Metadados pela consulta — verificado

O que o programa não tem como saber sai em `A DEFINIR`, nunca num nome plausível. Para
preencher sem que o programa invente nada, a rota aceita os campos na consulta:

```
/app/separador-3f/memorial?cliente=PETROBRAS&unidade=P-77&seq=042&rev=B
```

Verificado com o servidor no ar: o documento sai com
`MC-SENAI-SEP-ENG-**042-B**`, `CLIENTE: PETROBRAS`, `UNIDADE: P-77` — e o que **não** foi
informado continua em `A DEFINIR`, em vez de virar célula vazia. Campos aceitos:
`cliente`, `projeto`, `unidade`, `executor`, `seq`, `rev`; cada valor é escapado e
limitado a 120 caracteres, porque vai para dentro do bloco de título, que tem largura
fixa.

`app/smoke.jl` fixa o comportamento: `meta_da_consulta` lê os parâmetros defensivamente
(se a chave que o Genie usa mudar, os campos caem nos defaults em vez de derrubar a
rota), e sem o teste essa queda seria silenciosa.

### 10.1 O teto de decantação agora diz ATENDE — e por que não dizia

O motor sempre **impôs** `d ≤ d_max`: é assim que a admissibilidade funciona, e é por
isso que o vaso escolhido respeita o teto. Mas o `ResultField` "Teto de decantação"
tinha `status = :neutro` — informava o valor do teto, sem veredito sobre ele. A folha 04
lia o status e imprimia travessão numa conferência que o programa **de fato faz**.

Isso é pior que ausência: uma linha de VERIFICAÇÃO sem veredito, num documento assinado,
passa por verificada. E o memorial não podia corrigir sozinho — escrever ali um "atende"
que o motor não calculou é exatamente a falha que a regra existe para impedir.

A correção é no **core**, em `result_fields`: `_sob_o_teto` devolve `:ok` quando
`x ≤ teto`, `:erro` quando passa, e `:neutro` só quando não há teto (o vaso bifásico não
tem decantação líquido-líquido) ou não há resultado. Segue o **cursor**, como os demais
campos: arrastá-lo para além do teto mostra ✗.

Efeitos colaterais, assumidos: o cartão da tela ganha ✓ no teto, e `fecho_memorial` (que
filtra por `status !== :neutro`) passa a imprimi-lo na linha de fecho do `.txt`. Os dois
são informação verdadeira que antes não aparecia.

Para o exemplo do artigo: teto 9124 mm, vaso 6300 mm → **ATENDE**, com folga de 2824 mm.

`test/memorial.jl` passou a exigir que **toda** `VerificacaoDoc` aponte para um campo com
veredito no caso de referência — não mais só a esbeltez.

### 10.2 Eq. 15 e Eq. 23 agora trazem valor calculado

O `Lss` era o **único** resultado sem passo intermediário: a folha 03 mostrava as duas
regras com notação e referência, e travessão no valor.

A causa era onde o `Lss` nasce. `lss_from` é chamada dentro de `derived`, uma vez por
ponto da varredura; carimbar o `CalcTrace` ali encheria o memorial com uma linha por
diâmetro da grade. A correção foi carimbar em `trace_selection!`, que roda **uma vez**,
sobre o ponto escolhido — que é o que o documento descreve.

Qual equação citar depende de quem governa, então é hook (`lss_trace`) e não constante:
Eq. 15 quando o gás governa, Eq. 23 quando o líquido governa. O default cita
`SEM_EQUACAO` em vez de palpitar, como `slenderness_equation`.

A que **não** governou continua sem linha — não se registra conta que não se fez. No
caso de referência governa o líquido: `Eq. 23 → Lss = 24,78080 m`, e a Eq. 15 fica em
travessão.

---

## 11. Defeitos encontrados nesta passagem

**0 defeitos de física.** Nenhuma equação, referência ou número foi alterado: este passo
só documenta o que já estava implementado e verificado no [passo 4](04-separador-trifasico.md).

### 11.1 Duas correções de citação, ao escrever o `memorial_spec`

São exatamente o tipo de erro que a bijeção existe para pegar:

1. o volume do casco havia sido citado como saindo da Eq. 24 (a esbeltez) — não sai;
   virou `Geom.`, com a referência dizendo que não consta da fonte;
2. o diâmetro havia sido citado como saindo das Eq. 14/22 — elas dão o `Leff` exigido;
   o diâmetro sai do **critério de escolha**, que é a Eq. 24 sobre a grade admissível.

### 11.2 Quatro defeitos de composição, achados na conferência visual

Nenhum deles aparece em teste headless: são propriedades do documento **renderizado em
A4**, e só se veem no papel. Foram encontrados abrindo o memorial no navegador e
capturando as folhas.

| # | defeito | causa | correção |
|---|---|---|---|
| 1 | `MEMÓRIA DE CÁLCULO` quebrava em duas linhas e a segunda era **cortada**, no bloco de título de **todas** as folhas | 11 pt na banda G:O mede ~45 mm; a banda tem ~41 mm. O corpo tabelado no handoff pressupõe o escalonamento global da planilha (69 %), que este documento não reproduz | `white-space: nowrap` no bloco de título e o corpo ajustado (9 pt) |
| 2 | `SEM ESCALA` idem, na banda Z:AB | mesma causa | 6 pt, sem quebra |
| 3 | `A DEFINIR` em REVISOR e APROVAÇÃO estourava a coluna | o campo não é "faltou preencher": é emissão inicial **ainda não revisada** | os dois saem em branco — que é o que um quadro de revisões deve mostrar |
| 4 | O 4º bloco de equação era **cortado pela borda inferior**, saindo sem o `VALOR CALCULADO` | contagem fixa de 4 blocos por folha, mas os blocos não têm a mesma altura (2 variáveis na Eq. 9–11, 7 na Eq. 22) | repartição **por custo** — `paginar_por_custo`, com o custo em linhas de 13,5 pt |

O defeito 4 é o grave: violava a regra do handoff ("um bloco nunca é partido entre
folhas") justamente no elo que a folha 03 existe para mostrar. `app/smoke.jl` passou a
guardar o repartidor — nada se perde, nada se reordena, e nenhuma folha com dois ou mais
blocos estoura o orçamento.

Um quinto ajuste, de conteúdo: o resumo da folha de rosto trazia **duas linhas**
(o filtro por `highlight || status` é o de `fecho_memorial`, certo para resumir um caso
numa linha de texto e pobre para uma folha de rosto). Agora traz os oito campos.

Com a repartição por custo o documento do caso de referência passou de **11 para 12
folhas**: rosto, 2 de premissas/hipóteses, **6** de fórmulas (3 equações cada), 1 de
resultados e 2 de figuras.

### 11.3 Conferido no navegador

Com o servidor no ar e Firefox headless, sobre `exemplo_alves_komesu.toml`:

* **folha de rosto** — bloco de título completo e sem corte, `folha 1 de 12`, quadro de
  revisões só aqui, e o resumo com os oito campos batendo com o cartão da tela
  (6300 mm · 18,59 m · 24,78 m · SR 3,93 · 772 m³ · capacidade de líquido · Fim de vida
  · 9124 mm);
* **folha de fórmulas** — três blocos inteiros, cada um com notação em Times itálico,
  `ONDE:` com as variáveis e unidades, referência, validade e **valor calculado**
  (`C_D = 1,81403`, `V_t = 0,18933 m/s`, `Re = 26,82240`);
* **folha de resultados** — a coluna `EQUAÇÃO` amarrando cada valor ao bloco da folha 03,
  e as verificações com o veredito **real**: `ATENDE` na esbeltez, `—` no teto de
  decantação (ver §10.1).

---

## 12. Cobertura por método, e por que ela para onde para

| método | sigla | equações | folhas | estado |
|---|---|---|---|---|
| `stewart_arnold` (separador trifásico) | SEP | 18 | 12 | **completo** |
| `stewart_arnold_2f` (knockout bifásico) | VKO | 9 | 9 | **completo** |
| `arnold_electrostatic` (tratador) | TRE | 11 | 10 | **completo** |
| `moran` (bomba centrífuga) | BMB | — | — | não feito |
| `saari_lmtd` (trocador) | TRC | — | — | não feito |
| `pinch_kemp` (Análise Pinch) | PCH | — | — | não feito |

Os três vasos são a família de Stewart & Arnold, e foi por ela que a generalização
começou: compartilham `constraints.jl`, o contrato de `VesselConstraints` e a estrutura
de blocos A/B/C. O que muda entre eles é conteúdo, que é exatamente o que o
`MemorialSpec` existe para carregar.

Os três restantes **não** foram documentados, e o motivo é a regra dura do projeto —
*nenhuma equação, referência ou número pode ser inventado*:

**Bomba (`moran`).** Onze das quinze linhas do rastro saem com `"—"` no lugar da
equação, porque a fonte é um artigo de revista (Moran, *CEP*, 2016) cuja exposição é em
prosa, sem equações numeradas. As quatro que têm citação real (`Antoine`, `§ regime`,
`Colebrook`, `Darcy`) são as correlações clássicas, que o artigo usa mas não inventa.
Documentar as outras onze exigiria ou numerá-las com uma numeração que a fonte não tem —
e o número numa folha de memorial é uma **promessa de onde conferir** —, ou ler o artigo
para descobrir a estrutura dele. As fórmulas já estão no campo `formula` de cada
`TraceEntry`; o que falta é a proveniência, não a matemática.

**Trocador (`saari_lmtd`).** São **trinta** equações citadas, repartidas entre Saari
(LUT, caps. 3–6) e o método de Bell-Delaware na forma de Branan (`Br. 2-13` a
`Br. 2-29`). Transcrever trinta notações e suas variáveis com fidelidade é um trabalho do
mesmo tamanho do que este passo inteiro fez pelo separador, e feito às pressas é
exatamente onde nasceria uma citação errada — o tipo de defeito que a bijeção pega no
código mas que ninguém pega no *texto* da notação.

**Análise Pinch (`pinch_kemp`).** Não dimensiona equipamento: devolve alvos de energia de
uma **rede**. As folhas de "Resultados do dimensionamento" e "Verificações" não são a
forma certa para ele, e a folha 02 teria de tabelar N correntes em vez de um conjunto
fixo de entradas. Precisa de uma variante de estrutura documental, não de um
`memorial_spec` a mais. O mesmo vale para o separador dinâmico, que monitora no tempo.

Para os três, a infra está pronta e o caminho é o mesmo: escrever
`src/memorial_specs/<metodo>.jl`. `test/memorial.jl` é dirigido por tabela sobre o
registro, então qualquer um deles entra na bateria inteira ao ser declarado — sem editar
o teste.
