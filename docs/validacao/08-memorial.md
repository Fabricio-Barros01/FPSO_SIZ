# Passo 8 — Memorial de cálculo documental (seis módulos: SEP, VKO, TRE, BMB, TRC, PCH)

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
| Conteúdo, por módulo | SEP 18 eqs · VKO 9 · TRE 11 · BMB 8 · TRC 23 · PCH 5, cada um com premissas, hipóteses, resultados e verificações próprios | `src/memorial_specs/*.jl` |
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
| ~~1~~ | ~~Só três métodos têm `memorial_spec`~~ | **fechada** — os seis têm; ver §12 | — |
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

## 12. Cobertura por método — completa

| método | sigla | natureza | equações | folhas | verificações |
|---|---|---|---|---|---|
| `stewart_arnold` (separador trifásico) | SEP | dimensionamento | 18 | 12 | 2 |
| `stewart_arnold_2f` (knockout bifásico) | VKO | dimensionamento | 9 | 9 | 1 |
| `arnold_electrostatic` (tratador) | TRE | dimensionamento | 11 | 10 | 2 |
| `moran` (bomba centrífuga) | BMB | dimensionamento | 8 | 9 | 2 |
| `saari_lmtd` (trocador) | TRC | dimensionamento | 23 | 14 | 1 |
| `pinch_kemp` (Análise Pinch) | PCH | **metas** | 5 | 7 | 1 |

**Os seis módulos do catálogo que dimensionam ou calculam alvos têm memorial.** O único
box sem memorial é o **separador dinâmico** (Song 2023), que monitora no tempo e não
produz `SizingResult` — ver §12.4.

### 12.1 A proveniência de cada um, e como ela foi fechada

Nenhuma citação foi inventada. Onde a fonte numera equação, cita-se o número; onde não
numera, cita-se a localização real (seção, subseção, tabela, figura, página); e onde a
relação **não é da fonte**, isso está escrito.

| método | fonte | forma da citação |
|---|---|---|
| SEP | Alves & Komesu (2025) sobre Stewart & Arnold (2008) | `Eq. 9–24`, `Fig. 3`, e `Geom.` para o que não consta |
| VKO | Stewart & Arnold (2008), cap. 3 | `Eq. 3.x`, `§3.7`, `§3.8.4`, `§3.8.5` |
| TRE | Stewart & Arnold (2008), §4.7–4.9.6 | `Eq. 4.x`, `§4.9.1`, `§4.9.2` |
| BMB | Moran (CEP, dez/2016), pp. 38–44 | `Eq. 1` a `Eq. 7`, e `Hagen` para o acréscimo |
| TRC | Saari (LUT) **+** Branan (2012), cap. 2 | `Eq. 4.x`/`§x.y`/`Fig. 4.x` (Saari) e `Br. 2-xx`/`Tab. 4.1` (Branan) |
| PCH | Kemp (2007), 2ª ed. | `Tab. 2.2`, `§2.1.4`, `§3.7.3`, `§3.9.1`, `p. 24` |

As duas numerações do TRC convivem e são distinguíveis à vista, de propósito: o revisor
precisa saber em qual dos dois livros procurar.

### 12.2 O que mudou no SOLVER para fechar a proveniência

Documentar obrigou a corrigir atribuições no motor. Em nenhum caso mudou um número; em
todos, mudou **para onde o documento manda o revisor olhar**.

| método | antes | agora | por quê |
|---|---|---|---|
| BMB | `Re`, `Pv`, `NPSH`, `P` saíam como `—` | `Eq. 3`, `Eq. 5`, `Eq. 6`, `Eq. 7` | têm número na fonte; o travessão escondia a proveniência |
| BMB | `h_atrito` saía como `Darcy` | `Eq. 1/4` | nomeava a correlação do trecho reto e calava a dos acessórios, que no recalque costuma ser a maior |
| BMB | `f` saía como `Colebrook` | `Eq. 2` no turbulento; `Hagen` segue no laminar | a assimetria **é** a proveniência: `f = 64/Re` não consta do artigo |
| PCH | `§3.9.1 p. 8` (11 caracteres) | `§3.9.1`, com a página na coluna livre | estourava a coluna de 10 e saía `§3.9.1 p. 8QHmin` no `.txt` |
| todos os vasos | `Lss` sem linha de rastro | `Eq. 15`/`Eq. 23`/`§3.8.4`/`§4.9.1` | era o único resultado sem passo intermediário |
| todos os vasos | teto de decantação sem veredito | `:ok`/`:erro` por `_sob_o_teto` | o motor impunha `d ≤ d_max` e não o declarava |
| PCH | balanço de entalpia rastreado e não julgado | `:ok`/`:erro` por `_balanco_fecha` | um número sem o critério ao lado obriga quem confere a saber de cor |

O que **continua** em `—` continua por decisão, e o documento diz qual é qual: a
velocidade de uma bomba é continuidade, a carga estática é aritmética de cotas, a soma
`H` é soma, e o diâmetro escolhido é critério de projeto. A fonte não as numera, então
elas não entram na folha de fórmulas — o travessão ali é a afirmação de que **não há
onde conferir**.

### 12.3 O Pinch não é um memorial de equipamento, e a arquitetura acompanhou

A Análise Pinch devolve **alvos termodinâmicos de uma rede**, não um equipamento. Forçá-la
na estrutura dos outros cinco prometeria um casco que ninguém calculou.

O contrato ganhou `natureza`:

* `:dimensionamento` (default) — a seção de resultados se chama
  "RESULTADOS DO DIMENSIONAMENTO";
* `:metas` — chama-se **"METAS DE ENERGIA DA REDE"**, e o resumo da folha de rosto,
  "RESUMO DAS METAS".

E `verificacoes` passou a poder ser **vazia**, com a seção sumindo do documento quando é.
A regra é a mesma que já valia por linha: *uma VERIFICAÇÃO existe quando o motor emite um
veredito, e não existe quando não emite*. Imprimir a seção com travessões se leria como
conferência feita.

O Pinch acabou com **uma** verificação, e ela é genuína: o balanço de entalpia da p. 24,
`QCmin − QHmin = ΣQ_quente − ΣQ_frio`. Não é tautologia — o lado esquerdo vem da cascata
de calor e o direito da soma corrente a corrente, por rotas independentes —, e é o que
pega erro de dado e erro de cascata. Ela já era rastreada; passou a ser julgada.

### 12.4 O que segue sem memorial, e por quê

O **separador dinâmico** (`song_dinamico`, Song et al. 2023). Ele monitora no tempo: não
devolve `SizingResult`, não tem rastro de cálculo no formato `CalcTrace`, e a rota do
memorial o recusa explicitamente com 404 e a explicação. Um memorial dele seria um
terceiro tipo de documento — um relatório de simulação, com séries temporais em vez de
equações resolvidas uma vez —, e a estrutura para isso ainda não existe. A `natureza`
do contrato é o lugar por onde ele entraria.

### 12.5 Verificação da cobertura

`test/memorial.jl` é dirigido por tabela sobre o **registro**: todo método que declare
`memorial_spec` entra na bateria inteira sem editar o teste. Ele roda o método pelo
caminho genérico do contrato (`case_input` → `size_equipment`), e o Pinch entrou com o
caso de referência do livro, porque as correntes de uma rede são um grupo repetível e os
defaults não descrevem nenhuma.

`app/smoke.jl` acrescentou a guarda do **artefato**: todo método com memorial tem de
EMITIR o documento — folhas montadas, zero token por resolver, quadro de revisões só na
de rosto, seções obrigatórias presentes, título de resultados conforme a natureza, e
seção de verificações existindo se e somente se há verificação. A lista de casos é
comparada com o registro, para que um método novo não fique sem documento emitido em
teste nenhum.

---

## 13. Simbologia matemática, edição e o documento em disco

Três pontas que o passo 8 deixou abertas, e que se fecham juntas porque são a mesma
pergunta: **o que sai do programa quando alguém pede o memorial.**

### 13.1 As equações deixaram de ser uma linha de texto

Até aqui `EquacaoDoc.notacao` era tudo o que existia, e a faixa da folha 03 imprimia a
string escapada dentro de uma `<div>` em Times itálico — a tipografia do handoff sem a
notação do handoff, que pede a equação "por extenso, em notação matemática, nunca em
sintaxe de código". Em uma linha não há fração empilhada nem radical, e a Eq. 11 do
separador saía assim:

```
V_t = 0,0036 · [ ((ρ_l − ρ_g)/ρ_g) · (d_m/C_D) ]^(1/2)
```

O `^(1/2)` é sintaxe de código. Agora `EquacaoDoc` carrega **duas** colunas da mesma
equação, e ambas são obrigatórias — `tex` é argumento **posicional** do construtor, então
não há como registrar equação sem simbologia:

| coluna | para quê | onde aparece |
|---|---|---|
| `notacao` | uma linha de texto | o `.txt` exportado, o painel da tela |
| `tex` | subconjunto de LaTeX | a faixa da folha 03, convertida em MathML |

**As 74 equações dos seis métodos foram autoradas**, uma a uma, sem alterar nenhuma
`notacao`, nenhuma referência e nenhum número.

### 13.2 MathML gerado em Julia, e por que não uma biblioteca

`app/src/memorial/mathml.jl` converte o subconjunto em MathML. **Nenhuma dependência,
nenhum script no documento, nenhuma fonte nova.**

Uma biblioteca de renderização (KaTeX, MathJax) desfaria a propriedade que faz este
documento ser um arquivo: hoje ele não tem script nenhum, e é por isso que abre de
`saida/` com o programa fechado e imprime igual em qualquer navegador. Passaria a exigir
JavaScript para que a equação aparecesse, mais ~1 MB de fontes próprias dentro do bundle
do PackageCompiler. MathML Core é nativo nos três motores desde 2023, não pede fonte
própria e imprime.

O subconjunto é **fechado e declarado** (frações, radicais, scripts, delimitadores
escaláveis, grego, operadores, funções, texto). Comando ou caractere fora dele **lança** —
a mesma regra de `resolver` com token não resolvido, e pela mesma razão: uma faixa vazia
num documento assinado é pior que uma exportação que falha.

Duas divergências deliberadas em relação ao LaTeX, ambas por causa do idioma e do
domínio: `0,0036` é um número só (em LaTeX seria `0{,}0036`), e letras seguidas são um
identificador só (`Re`, e não *R·e*) — a notação de engenharia é cheia de símbolos de
duas letras, e a multiplicação nestas equações é sempre explícita.

**Onde o MathML não entra:** a lista `ONDE:`. O handoff a especifica como
`símbolo = descrição (unidade)`, e `VariavelDoc.simbolo` é escrito na convenção da
`notacao` (`ρ_l`, `(h_o)_max`, `A_w/A`), não em LaTeX. Passá-la pelo conversor exigiria
autorar `tex` para ~300 variáveis, e até lá o conversor leria `d_max` como *d* subscrito
*m* seguido de *ax*: simbologia **errada**, que é pior que simbologia simples.

### 13.3 O documento se deixa corrigir antes de imprimir

Cada folha recebe `contenteditable`. É o que o protótipo do handoff já fazia
(`References/memorial-de-calculo-editavel.html`), e fecha por caminho manual a **lacuna
nº 2** do §10: cliente, unidade e executor saem `A DEFINIR` quando a consulta não os
traz, e quem imprime nem sempre é quem gera.

Continua **sem script** — `contenteditable` é do navegador. A edição vive na aba e **não
volta para o programa**, de propósito: um memorial editado à mão não é o memorial que o
motor calculou, e gravá-lo de volta apagaria a distinção entre o que foi computado e o
que foi digitado. O realce de edição é regra de tela, desfeita em `@media print`.

### 13.4 O memorial A4 agora chega ao disco

`exportar!` passou a gravar `<base>_memorial.html` ao lado do CSV, do `.txt` e das
figuras. São **dois memoriais, e continuam sendo dois** — é a lacuna nº 5 do §10, que
segue valendo:

| arquivo | o que responde |
|---|---|
| `_memorial.txt` | o **rastro**, de todos os casos de canto do envelope |
| `_memorial.html` | o **documento** de quatro folhas do caso governante — o que se assina |

O `.html` é **autocontido**: o `memorial.css` vai embutido em `<style>` (no lugar do
`<link href="/memorial.css">`, que de `saida/` não resolveria para nada), e a marca do
emitente vai como `data:` URI. Abre por duplo clique, com o programa fechado, e o
Ctrl+P produz o PDF paginado.

O CSS embutido é lido de `dir_publico()` — a **mesma** origem que o servidor usa. Não há
segunda cópia do estilo a divergir, e o arquivo exportado imprime exatamente como a rota.

**O formato XLSX do handoff não entra.** `app/src/memorial/documento.jl` registra desde o
passo 8 a escolha de HTML → impressão no lugar da planilha; retomá-la seria dependência
nova e a grade de 28 colunas reimplementada em mesclagens. Não é lacuna, é a decisão.

### 13.5 O que ficou em aberto

| # | observação | por que não se mexeu |
|---|---|---|
| 1 | As folhas de fórmulas sobram ~25 % no pé | O custo de paginação (`5 + ⌈nvars/2⌉`) cobra altura fixa por faixa, e as faixas agora variam: a Eq. 11 ocupa o triplo de `F = 1`. O modelo subestima a equação alta e superestima a baixa — mas erra para o lado **seguro**, e nenhuma folha estoura. Retunar o orçamento sem um custo sensível à altura trocaria papel em branco por risco de corte. |
| 2 | A lista `ONDE:` não é MathML | §13.2 |

### 13.6 Verificação

```sh
julia --project=.   test/runtests.jl     # 5319 passam, 4 broken (pré-existentes)
julia --project=app app/smoke.jl         # 3634 passam
```

Guardas novas:

| guarda | o que impede |
|---|---|
| `tex` não-vazio em toda equação (core) | faixa muda no documento |
| toda `tex` dos seis métodos converte (smoke) | o subconjunto testado só contra si mesmo |
| uma `<math>` por faixa, nenhum `<merror>`, `]^(1/2)` ausente | a notação de uma linha voltar à faixa |
| o conversor lança em comando/caractere/chave desconhecidos | símbolo desconhecido sair em silêncio |
| `contenteditable` em toda folha servida | o documento deixar de se corrigir |
| o `.html` exportado sem `href="/memorial.css"`, sem `{{`, com `@page` e com a marca embutida | o arquivo em `saida/` não abrir fora do servidor |
| a exportação grava exatamente sete arquivos, um por sufixo | o total mudar sem que se saiba qual arquivo mudou |

Conferido no navegador, com o arquivo aberto de `file://` e o servidor derrubado: as doze
folhas do separador montam, a Eq. 11 sai com o radical cobrindo a fração, a Fig. 4.3 do
trocador (fração dentro de fração, dois radicais) cabe na faixa sem corte, e o caso-ouro
continua **6300 mm · 18,59 m · 24,78 m · SR 3,93**.
