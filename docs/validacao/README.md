# Fase de validação física — índice

Relatórios da fase que confronta, método por método, **a física implementada contra a
fonte bibliográfica que a define**. Cada um traz: tabela equação-do-código × equação-da-
referência, auditoria dimensional, limites de validade declarados versus verificados,
casos-ouro com desvio e tolerância justificada, defeitos classificados, e lacunas.

| # | Relatório | Método | Fonte | Defeitos |
|---|---|---|---|---|
| 0 | [Linha de base](00-linha-de-base.md) | — | — | — |
| 1 | [Bomba centrífuga](01-bomba-moran.md) | `:moran` | Moran, CEP dez/2016 | **2** |
| 2 | [Trocador casco-e-tubos](02-trocador-saari-bell-delaware.md) | `:saari_lmtd` | Saari (LUT) + Branan cap. 2 | **7** |
| 3 | [Tratador eletrostático](03-tratador-eletrostatico.md) | `:arnold_electrostatic` | Stewart & Arnold §4.7–4.9.6 | 0 |
| 4 | [Separador trifásico](04-separador-trifasico.md) | `:stewart_arnold` | Alves & Komesu (2025) + S&A cap. 4 | 0 |
| 5 | [Vaso flash / knockout](05-vaso-flash-knockout.md) | `:stewart_arnold_2f` | Stewart & Arnold cap. 3 | 0 |
| 6 | [Análise Pinch](06-pinch-kemp.md) | `PinchAnalysis` — não dimensiona | Kemp 2ª ed., caps. 2–3 | 0 |
| 7 | [Separador dinâmico](07-separador-dinamico-song.md) | `dynamics` — não dimensiona | Song et al., ACS Omega 2023 | 0 |
| 8 | [Memorial de cálculo](08-memorial.md) | `memorial` — camada documental | handoff de design + Alves & Komesu (2025) | 0 |

## Resultado global

| | antes | depois |
|---|---|---|
| Testes | **1.916** | **2.318** |
| Falhas | 0 | **0** |
| Tempo do `@testset` | 22,2 s | ~28 s |
| Equações conferidas contra a fonte | — | **86** |
| Defeitos corrigidos | — | **9** |
| Erratas de fonte documentadas | 5 | **12** |
| Casos de exemplo viáveis | 5 de 5 | **5 de 5** |

## Defeitos encontrados e corrigidos

| # | Método | Defeito | Classe | Teste que o expõe |
|---|---|---|---|---|
| 1 | bomba | detectava operação fora da faixa de Colebrook-White e **descartava o sinal**: o DN escolhido podia vir da zona de transição sem que nada avisasse | **físico** | `"fora da faixa de Colebrook-White o ponto é recusado"` |
| 2 | bomba | o memorial creditava `f` a Colebrook-White mesmo quando o número vinha de Hagen-Poiseuille | de unidade | `"e o memorial credita a equação que de fato produziu f"` |
| 3 | trocador | Dittus-Boelter aplicada fora de `10⁴ < Re < 1,2×10⁵` em silêncio, com `h_i` atravessando `U → A → L` | **físico** | `"fora da faixa de Dittus-Boelter o feixe é recusado"` |
| 4 | trocador | o diâmetro do feixe usava empacotamento triangular nos **quatro** layouts; a Eq. (2-14) de Branan, quadrada, não estava implementada (−7,5 % em 45°/90°) | **físico** | `"Eq. 2-13 e 2-14 — a área de célula depende do layout"` |
| 5 | trocador | o casco recebia a folga **casco-chicana** (Tab. 2-7, ~3 mm) no lugar da folga **casco-feixe** (Eq. 2-17, `2·d_o` = 38 mm) — 12× menor, `Jb` 0,98 em vez de 0,83, `h_o` 23–28 % **superestimado** | **físico** | `"Eq. 2-17 — o casco é o feixe mais dois diâmetros de tubo"` |
| 6 | trocador | o docstring de `f_correction_1_2` reproduzia o `R` **invertido** da Fig. 4.3 de Saari (o código sempre esteve certo) | de unidade | verificado por rota P-NTU independente |
| 7 | trocador | o `note` de `h_casco` citava a Tabela 4.1 como ordem de grandeza de `h_o` — mas ela tabela `U`, não coeficiente de película | de unidade | — (correção de documentação) |
| 8 | trocador | a divergência do `0,044` da Eq. (2-23) não estava documentada | de unidade | `"Eq. 2-23 — o 0,044 do segundo colchete é erro de digitação"` |
| 9 | trocador | `d_casco_max` (limite de **casco**, Tab. 3.1) era comparado com o **feixe** | de unidade | dentro do teste da Eq. 2-17 |

Nenhum defeito **numérico** foi encontrado: as iterações (Colebrook-White, arrasto,
ponto fixo de `L`) convergem, devolvem o flag de convergência, e o flag é consumido.

## Erratas das fontes

Cinco já estavam documentadas antes desta fase e foram **confirmadas na fonte**; cinco
são novas.

| fonte | equação | o que imprime | o que vale | como se decidiu |
|---|---|---|---|---|
| Alves & Komesu | Eq. (22) | `4,12×10⁴` | `4,2004×10⁴` (implícito na Tabela 3) | a tabela do próprio artigo, dispersão ±0,02 % |
| Stewart & Arnold | Eq. (4.5b) | `0,0033` | `0,033` | análise dimensional dá 0,0327; e a Eq. (4.6b) do próprio livro |
| Stewart & Arnold | Eq. (4.9b) | `1520` | `1320` | a forma geral com 0,033, e a Eq. (4.9a) de campo |
| Stewart & Arnold | Exemplo 3.2 | `d·L_eff = 55,04` | `39,85` | 7 de 7 linhas da Tabela 3.4 fecham com 39,85 |
| Saari | Exemplo 4.1 | `ṁ_água = 0,20 kg/s` | `0,30` | a solução usa 1260 W/K; com 0,20 o exemplo é impossível |
| Saari | Exemplo 4.1 | "3.6 metre elements" | `1,8 m` | a própria conta divide por 1,8 |
| **Saari** | **Fig. 4.3** | `R₁ = ΔT₁/ΔT₂` | `ΔT₂/ΔT₁` | contradiz a Eq. (4.11)/(4.12) do próprio texto; rota P-NTU confirma |
| **Branan** | **Eq. (2-21)** | `1,33/(PR/d_o)` | `1,33/PR` | `PR` é adimensional; a forma impressa muda com a unidade de `d_o` |
| **Branan** | **Eq. (2-23)** | `[1 − 0,044(1−r_a)]` | `[1 − 0,44(1−r_a)]` | com 0,044 o fator daria **1,396** a vazamento nulo |
| **Branan** | **Eq. (2-26)** | `θ₂ = arccos(…)` | `2·arccos(…)` | sem o 2 a área da janela sai 6,8× menor que o segmento |
| **Branan** | **Tab. 2-5** | 90°/Re 0–10: `a₂ = 0,667` | `−0,667` | as outras 19 linhas trazem o menos; `j` tem de cair com `Re` |
| **S&A** | **Tab. 3.4** | `L_ss` com `+2,5` constante | `+d/12` pela Eq. (3.10a) | não reproduzível pela equação publicada; o caso-ouro não testa essa coluna |
| **Kemp** | **§2.1.4 e §3.3** | o apêndice é a *"Section 3.11"* | **§3.9** | não existe §3.11; o cap. 3 termina em §3.9, e o índice traz o número certo |
| **Kemp** | **p. 24** | cargas *"510 and 470 kWh"* | **kW** | `CP` [kW/K] × `T` [°C] = kW; a Tabela 2.3 e a Fig. 2.6 do mesmo exemplo usam kW |

Todas foram decididas **por dentro** — coerência dimensional, coerência com outra equação
do mesmo texto, ou um limite conhecido a priori — e nunca por preferir outra fonte.

## Como as fontes foram lidas

| fonte | cifrado? | como |
|---|---|---|
| Moran, *Pump Sizing* (CEP) | **sim** — AES-128, `copy:no`, `print:yes` | páginas **rasterizadas** (`pdftoppm`, usando a permissão de impressão que o documento concede) e lidas |
| Saari, *Heat Exchanger Dimensioning* | não | texto extraído |
| Branan, *Rules of Thumb* | não | texto extraído + páginas 42–43 rasterizadas para conferir sinais da Tab. 2-5 |
| Stewart & Arnold | não | texto extraído |
| Alves & Komesu (2025) | não | texto extraído + páginas 8–9 rasterizadas (as equações são objetos do Word) |
| Kemp, *Pinch Analysis and Process Integration*, 2ª ed. | não | texto extraído |

## Decisões tomadas pelo usuário nesta fase

1. **Fora da faixa declarada, recusar** — não sinalizar e seguir. *"Um ponto fora do
   domínio de validade da correlação não é necessariamente fisicamente impossível; ele é
   simplesmente um ponto que o modelo matemático implementado não está autorizado a
   avaliar. Portanto, deve ser rejeitado como candidato do modelo, com o motivo
   explicitado."* Aplicado aos defeitos 1 e 3.
2. **Corrigir a área de célula por layout** (defeito 4), preservando o resto da
   metodologia e com teste mostrando que só os layouts quadrados mudam.
3. **Corrigir a folga do casco** para a Eq. (2-17) (defeito 5), ciente de que muda todos
   os resultados de trocador.
4. **Não enforçar o piso de `F < 0,75`**: nenhuma fonte do projeto o declara.

## Lacunas que a fase não fechou

| # | lacuna | método |
|---|---|---|
| 1 | não há caso-ouro de linha inteira `(Q, H)` | bomba |
| 2 | não há caso-ouro com o laço de `U` fechado | trocador |
| 3 | não há caso-ouro nenhum | tratador |
| 4 | só um caso de validação, e o `L_ss` do outro não é reproduzível | separador, knockout |
| 5 | faixa de `T` da Antoine não verificada (A, B, C são entrada; a faixa não) | bomba |
| 6 | faixa de `Re` do coeficiente de arrasto não declarada por nenhuma fonte | separador, knockout |
| 7 | limite de Stokes (`Re` de gotícula ≲ 1) não declarado nem verificado — **medido em 0,49 e 0,64 no caso default**, dentro | tratador, separador |
| 8 | nº de passes × diâmetro do casco (Tab. 3.1) não verificado | trocador |
| 9 | `µ/µ_parede = 1`, rugosidade e `ΔT` de parede na Eq. (6.23) | trocador |
| 10 | o campo elétrico não é dimensionado — a referência que o fecharia não está em `References/` | tratador |

As lacunas 5, 7 e 8 são candidatas naturais a uma rodada de fecho: as três são
verificações de faixa, e as três dependem de uma decisão sobre enforçar um limite que a
fonte **não** declara — que é a mesma pergunta que o piso de `F` respondeu com "não".
