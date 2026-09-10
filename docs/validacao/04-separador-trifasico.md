# Passo 4 — Separador trifásico horizontal

**Método:** `:stewart_arnold` · **Equipamento:** `:separator`
**Fontes:**
- Alves, C. & Komesu, A. (2025), *Latin American Journal of Energy Research* v. 12, n. 1,
  pp. 16–29 — Eq. (9) a (24), Figuras 3 e 4, Tabelas 1 a 4. **14 páginas, não cifrado.**
- Stewart, M. & Arnold, K. (2008), *Gas-Liquid and Liquid-Liquid Separators*, cap. 3 e 4 —
  a fonte primária que o artigo reproduz.

**Arquivos:** [stewart_arnold.jl](../../src/sizing/separator/stewart_arnold.jl),
[drag.jl](../../src/sizing/separator/drag.jl),
[gas_capacity.jl](../../src/sizing/gas_capacity.jl),
[beta.jl](../../src/sizing/separator/beta.jl),
[constraints.jl](../../src/sizing/constraints.jl),
[stewart_arnold.toml](../../config/equipment/separator/stewart_arnold.toml)

É o método com o **caso-ouro mais forte** dos cinco: uma tabela publicada de seis linhas
× três grandezas, mais duas tabelas auxiliares e a comparação com um vaso instalado.

---

## 1. Equação do código × equação da referência

| # | Forma publicada | Código | Veredito |
|---|---|---|---|
| Eq. (9) | `C_D = 24/Re + 3/√Re + 0,34` | [drag.jl:44](../../src/sizing/separator/drag.jl#L44) | **equivalente** — literal |
| Eq. (10) | `Re = 0,001·ρ_g·d_m·V_t/µ_g` | [drag.jl:37](../../src/sizing/separator/drag.jl#L37) | **equivalente** — literal; coeficiente derivado em §2.2 |
| Eq. (11) | `V_t = 0,0036·[((ρ_l−ρ_g)/ρ_g)(d_m/C_D)]^½` | [drag.jl:29](../../src/sizing/separator/drag.jl#L29) | **equivalente** — literal; ver §2.3 |
| Eq. (12) | `ρ_l = ρ_w·141,5/(131,5 + °API)` | [units.jl](../../src/units.jl) `api_to_density` | **equivalente** — literal |
| Eq. (13) | `K = [(ρ_g/(ρ_l−ρ_g))(C_D/d_m)]^½` | [drag.jl:88](../../src/sizing/separator/drag.jl#L88) | **equivalente** — literal |
| Eq. (14) | `d·L_eff = 34,5·[T·Z·Q_g/P]·K` | [gas_capacity.jl:56](../../src/sizing/gas_capacity.jl#L56) | **equivalente** — literal; ver §2.4 |
| Eq. (15) | `L_ss = L_eff + d/1000` | [constraints.jl:145](../../src/sizing/constraints.jl#L145) (ramo `:gas`) | **equivalente** — literal |
| Eq. (16) | `ΔSG = (SG)_w − (SG)_o` | [stewart_arnold.jl:143](../../src/sizing/separator/stewart_arnold.jl#L143) | **equivalente** — literal |
| Eq. (17) | `(h_o)max = 0,033(t_r)_o(ΔSG)d²_m/µ_o` | [:150](../../src/sizing/separator/stewart_arnold.jl#L150) | **equivalente** — literal; coeficiente derivado em `03-*.md` §2.1 |
| Eq. (18) | `A_w/A = 0,5·Q_w(t_r)_w/[(t_r)_oQ_o + (t_r)_wQ_w]` | [beta.jl:97](../../src/sizing/separator/beta.jl#L97) | **equivalente** — literal |
| Fig. 3 | β = h_o/d contra A_w/A, cilindro meio cheio, eixo vertical **invertido** | [beta.jl:79](../../src/sizing/separator/beta.jl#L79) `beta_coefficient` | **equivalente após rearranjo** — ver §2.5 |
| Eq. (19) | `d_max = (h_o)max/β` | [:165](../../src/sizing/separator/stewart_arnold.jl#L165) | **equivalente** — literal |
| Eq. (20) | `(h_w)max = 0,033(ΔSG)(t_r)_w d²_m/µ_w` | [:151](../../src/sizing/separator/stewart_arnold.jl#L151) | **equivalente** — literal |
| Eq. (21) | `d_max = (h_w)max/**β**` | [:166](../../src/sizing/separator/stewart_arnold.jl#L166) | **segue o publicado** — divergência 3 |
| Eq. (22) | `d²L_eff = **4,12×10⁴**((t_r)_oQ_o + (t_r)_wQ_w)` | [:190](../../src/sizing/separator/stewart_arnold.jl#L190) usa **4,2152×10⁴** | **divergente** — divergência 1 |
| Eq. (23) | `L_ss = (4/3)L_eff` | [constraints.jl:145](../../src/sizing/constraints.jl#L145) (ramo `:liquid`) | **equivalente** — literal |
| Eq. (24) | `SR = L_ss/(d/1000)` | [constraints.jl:233](../../src/sizing/constraints.jl#L233) | **equivalente** — literal |
| Tab. 1 | condições e propriedades | `config/stream.toml` | **equivalente**, com a ressalva da divergência 2 |

### Divergências

| # | O que a fonte imprime | O que o código faz | Como foi decidido |
|---|---|---|---|
| 1 | Eq. (22): `4,12×10⁴` | `4,2152×10⁴` | **O valor impresso é inconsistente com a Tabela 3 do próprio artigo**, que implica `4,2004×10⁴` (§4.2). O adotado é derivado da forma de campo de Stewart & Arnold (`1,42`) por conversão de unidades pura. Reproduz a Tabela 3 com +0,35 %; o `4,12×10⁴` erra −1,91 %. **Checável por dentro** |
| 2 | Tab. 1: `µ_gás = 0,6 cP` | `µ_g` é entrada explícita, default 0,012 cP | A Tabela 1 repete **`1,1` para densidade relativa E viscosidade da água**, e **`0,6` para as duas do gás** — as colunas foram trocadas na transcrição. Gás natural a 28 °C / 2300 kPa fica em ~0,012 cP; 0,6 cP é viscosidade de líquido. **Verificado na tabela renderizada** (§4.3) |
| 3 | Eq. (21): `d_max = (h_w)max/β` | **segue o publicado**, e emite a variante geométrica como `Eq. 21*` | β **é** a altura fracionária do óleo (a Figura 3 rotula o eixo `β = h_o/d`); a da água num vaso meio cheio é `0,5 − β`. Dividir a espessura máxima de água pela fração de óleo usa a cota errada. **Seguimos o texto publicado** porque o propósito declarado é reproduzir o artigo, e mudar a equação faria o caso-ouro deixar de reproduzi-lo — mas a variante é calculada e vai ao memorial. Ver §5 |
| 4 | Eq. (15)/(23): o artigo aplica a relação do bloco **que governa** | idem (segue o artigo) | Stewart & Arnold §4.9.1 manda tomar o **maior** dos dois. O artigo simplifica. Seguimos o artigo aqui, e o **livro** no vaso bifásico e no tratador, cuja fonte é ele. Ver §6 |

---

## 2. Auditoria dimensional

### 2.1 Onde `Units` é aplicado

`field_units` é o **único** ponto de conversão, e este é o método para o qual ele foi
escrito: todas as correlações de Stewart & Arnold trabalham em unidades de campo
métricas (`mm`, `m`, `m³/h`, `cP`, `kPa`, `K`, `µm`, `min`). O core guarda SI; `field_units`
converte uma vez; nenhuma função de `sizing/separator/` chama `Units` diretamente.

Verificado: `stewart_arnold.jl` **não importa nem menciona `Units`**. A única divisão por
1000 do caminho é o `d/1000` da Eq. (15)/(24), que é a conversão mm→m do diâmetro dentro
da própria equação publicada.

### 2.2 O `0,001` da Eq. (10) — fecha exato

`Re = ρvd/µ`, com `ρ` em kg/m³, `v` em m/s, `d_m` em **µm** (`×10⁻⁶` m) e `µ_g` em **cP**
(`×10⁻³` Pa·s):

```
Re = ρ·v·(d_m·10⁻⁶)/(µ_g·10⁻³) = 10⁻³ · ρ·v·d_m/µ_g
```

**`0,001` exato.** ✓

### 2.3 O `0,0036` da Eq. (11) — e um achado numérico de baixo impacto

A velocidade terminal de uma gotícula é `V_t = √(4·g·d·(ρ_l−ρ_g)/(3·C_D·ρ_g))`. Com `d`
em µm:

```
V_t = √(4·9,81·10⁻⁶/3) · √[((ρ_l−ρ_g)/ρ_g)(d_m/C_D)]
    = 3,6166×10⁻³ · √[…]
```

O publicado é `0,0036`, que **trunca 0,46 %**. Fica registrado como achado numérico e
**não** foi alterado:

- é o valor que a fonte publica, e o critério do projeto é seguir a fonte salvo quando
  ela se contradiz — o que aqui não acontece;
- o impacto é nulo no resultado. `V_t` entra **só** no Reynolds da iteração de arrasto
  (Eq. 10), e o produto que sai do bloco A é `K` (Eq. 13), que **não usa `V_t`**. Um
  desvio de 0,46 % em `V_t` desloca o `Re` em 0,46 % e o `C_D` convergido em muito menos;
- e o bloco A não governa neste caso (§4.4).

### 2.4 O `34,5` da Eq. (14) — 0,87 % acima do equivalente exato do `420`

A forma de campo de Stewart & Arnold é `d·L_eff = 420·[TZQ_g/P]·K`. Convertendo
(in²·ft → mm²·m, °R → K, MMscfd → m³/h, psi → kPa):

```
34,5_equiv = (25,4 × 0,3048) × 420 × 1,8 × [24/(10⁶ × 0,0283168)] × 6,894757 = 34,202
```

O `34,5` publicado fica **+0,87 %** acima. **Segue-se o publicado**: 0,87 % não muda vaso
nenhum, as duas formas concordam a menos de 1 %, e não há contradição interna a resolver.
É o contraste deliberado com a Eq. (22), cujo impresso erra 1,9 % contra a **tabela do
próprio artigo** — ali há contradição, e por isso ali o valor é derivado.

### 2.5 Figura 3 — β é geometria pura, e não precisa ser digitalizado

A Figura 3 relaciona `A_w/A` com `β = h_o/d` para um cilindro **meio cheio**, com o eixo
vertical **invertido** (0,0 no topo, 0,5 na base) e a curva indo de `(0 , 0,5)` a
`(0,5 , 0)`. O inset da figura mostra `A_o` acima de `A_w` com `h_o + h_w = d/2`.

Isso é exatamente o que a geometria manda, e por isso a curva é **derivável** em vez de
lida:

```
β = h_o/d = 0,5 − h_w/d,   com h_w a altura do segmento circular de área (A_w/A)·πR²
```

`beta_coefficient` resolve o segmento por bisseção. Vantagem sobre digitalizar: exato,
sem erro de leitura de régua, e barato — o motor de envelope avalia β dezenas de milhares
de vezes. Conferido nos pontos de controle e nos intermediários
([test/beta.jl](../../test/beta.jl)): `A_w/A = 0,1 → β ≈ 0,344`; `0,25 → β ≈ 0,202`;
`0,4131 → β ≈ 0,0685`.

Os dois extremos saem **exatos** e não pela bisseção, deliberadamente: `0,5 − h(0,5)`
devolveria `1,1×10⁻¹⁶` em vez de zero, e um β de `10⁻¹⁶` é a diferença entre "sem óleo" e
"camada de óleo de espessura nula dividindo `(h_o)max` por ela" — que é `Inf` no teto.

### 2.6 Coerência dimensional dos três blocos

| bloco | expressão | unidades |
|---|---|---|
| A | `34,5·[K·(m³/h)/kPa]·[–]` | mm·m ✓ |
| B | `[mm·cP/(min·µm²)]·[min]·[–]·[µm²]/[cP]` | mm ✓ |
| B | `d_max = [mm]/[–]` | mm ✓ |
| C | `[mm²·m·h/(min·m³)]·([min]·[m³/h])` | mm²·m ✓ |
| geometria | `L_eff = max(d·L_eff/d , d²·L_eff/d²)` com `d` em mm | m ✓ |
| esbeltez | `SR = L_ss/(d/1000)` | adimensional ✓ |

---

## 3. Limites de validade: declarados × verificados

| limite | declarado pela fonte | verificado no código | veredito |
|---|---|---|---|
| iteração de `C_D` (Eq. 9–11) | "tentativa e erro até encontrar o valor" | `converge_drag` devolve `converged`; `gas_capacity_dleff` **recusa** com mensagem se não convergir | **verificado** |
| faixa de `Re` da Eq. (9) | **não declarada** | não verificado | **lacuna** — ver §6 |
| Stokes (Eq. 17/20) | **não declarada** | não verificado | **lacuna** — ver §6 |
| esbeltez | 3 a 5 (Eq. 24 e §4.9.2) | `sr_min`/`sr_max` em `admissible` | **verificado** |
| teto de decantação | Eq. (19)/(21) | `ceiling_of` recorta a grade, com mecanismo nomeado | **verificado** |
| ΔSG > 0 | implícito | checado, com mensagem própria | **verificado** |
| β > 0 | implícito | checado, com mensagem própria | **verificado** |
| nível de líquido 50 % | Tab. 1 e Fig. 3 | **fixo por construção** (β é do vaso meio cheio) | **verificado** — quem quiser outro nível usa a família de §4.9.4 |

---

## 4. Casos-ouro

O mais forte dos cinco: **três tabelas publicadas e uma comparação com equipamento real.**

### 4.1 Tabela 3 — a varredura completa, 18 valores

Grade do artigo (5200 a 5950 mm, passo 150), dados da Tabela 1.

| d (mm) | `L_eff` pub. | calc. | desvio | `L_ss` pub. | calc. | desvio | SR pub. | calc. | desvio |
|---|---|---|---|---|---|---|---|---|---|
| 5200 | 19,29 | 19,355 | **+0,34 %** | 25,71 | 25,807 | **+0,38 %** | 4,94 | 4,963 | **+0,46 %** |
| 5350 | 18,22 | 18,285 | +0,36 % | 24,29 | 24,380 | +0,37 % | 4,54 | 4,557 | +0,37 % |
| 5500 | 17,24 | 17,301 | +0,35 % | 22,98 | 23,068 | +0,38 % | 4,18 | 4,194 | +0,34 % |
| 5650 | 16,34 | 16,395 | +0,33 % | 21,78 | 21,860 | +0,37 % | 3,86 | 3,869 | +0,23 % |
| 5800 | 15,50 | 15,558 | +0,37 % | 20,67 | 20,744 | +0,36 % | 3,56 | 3,576 | +0,46 % |
| 5950 | 14,73 | 14,783 | +0,36 % | 19,64 | 19,711 | +0,36 % | 3,30 | 3,313 | +0,39 % |

**Tolerância adotada: `rtol = 0,005` (0,5 %).**

*Justificativa.* O desvio real é **+0,33 % a +0,46 % nos dezoito valores**, e é
sistemático, não disperso — é o mesmo +0,35 % em toda parte, que é exatamente a razão
`4,2152×10⁴ / 4,2004×10⁴`. Ou seja: **o desvio não é erro de cálculo, é a diferença entre
o coeficiente derivado por conversão de unidade e o coeficiente implícito na planilha
Excel do artigo.** A tolerância de 0,5 % é a menor que acomoda essa diferença conhecida e
quantificada, e é apertada o bastante para reprovar o `4,12×10⁴` impresso, que erra 1,9 %
— e há um teste que verifica justamente isso, como guarda de regressão.

### 4.2 O coeficiente que a Tabela 3 implica

Com `(t_r)_o Q_o + (t_r)_w Q_w = 10×215,8 + 10×1025,8 = 12.416`:

| d (mm) | `d²·L_eff` | `C` implícito |
|---|---|---|
| 5200 | 5,2160×10⁸ | 42.010,4 |
| 5350 | 5,2150×10⁸ | 42.002,4 |
| 5500 | 5,2151×10⁸ | 42.003,1 |
| 5650 | 5,2161×10⁸ | 42.011,4 |
| 5800 | 5,2142×10⁸ | 41.995,8 |
| 5950 | 5,2148×10⁸ | 42.000,5 |
| | **média** | **42.003,9** |

| candidato | desvio da média implícita |
|---|---|
| **`42.152,1`** (derivado do `1,42` de campo — o que o código usa) | **+0,35 %** |
| `41.200` (o `4,12×10⁴` impresso na Eq. 22) | **−1,91 %** |

A dispersão do `C` implícito entre as seis linhas é de apenas ±0,02 %, o que mostra que a
planilha do artigo usou **um** coeficiente consistente — e que ele não é o `4,12×10⁴` que
o texto imprime. **O erro tipográfico é do texto, não da tabela.**

### 4.3 Tabela 1 — a troca de colunas, verificada na fonte

| propriedade | valor publicado |
|---|---|
| Peso Específico da Água | **1,1** |
| Viscosidade da Água | **1,1** cP |
| Peso Específico do Gás | **0,6** |
| Viscosidade do Gás | **0,6** cP |
| Peso Específico do Óleo | 0,9 |
| Viscosidade de Óleo | 10 cP |

A repetição exata do par (`1,1`, `1,1`) para a água e (`0,6`, `0,6`) para o gás é a
assinatura de colunas trocadas na transcrição. Gás natural a 28 °C e 2300 kPa tem
viscosidade de ~0,012 cP; `0,6 cP` é viscosidade de líquido.

Sensibilidade medida: `µ_g = 0,012` dá `L_eff,gás ≈ 0,065 m` (que **é** a Tabela 2 do
artigo) e `µ_g = 0,6` dá `≈ 1,6 m`. Em nenhum dos dois o gás governa, então **a conclusão
do artigo se mantém** — e é por isso que `µ_g` é exposto como entrada explícita, com a
escolha visível, em vez de embutido.

*(Observação: a Tabela 1 também lista "Peso Específico do Óleo = 0,9" ao lado de
"Densidade do Óleo = 863 kg/m³", que dá 0,863; e o °API 32 dá 0,865 pela Eq. 12. O código
usa a densidade, não o peso específico arredondado.)*

### 4.4 Tabela 2 — a capacidade de gás não governa

O artigo tabula `L_eff,gás` de 0,05 a 0,06 m nas seis linhas e conclui que a separação
líquido/líquido é a principal. O teste reproduz a **ordem de grandeza** e, sobretudo, a
**conclusão**: `per_constraint[:gas] < 0,1 m` e `< per_constraint[:liquid]/100` em toda a
grade, e `res.governing === :liquid`.

Comparar linha a linha com tolerância relativa seria comparar com o arredondamento da
publicação — a tabela traz **duas casas decimais** num número da ordem de 0,05, onde meia
casa vale 10 %. O que a Tabela 2 de fato fixa é a conclusão, e é contra ela que se testa.

### 4.5 Tabela 4 — contra o vaso instalado (Martins, 2017)

| dimensão | calculado (artigo) | real instalado | este programa | desvio vs. real |
|---|---|---|---|---|
| `d` | 5,50 m | 5,30 m | 5,50 m | **+3,8 %** |
| `L_eff` | 17,24 m | 19,00 m | 17,30 m | **−8,9 %** |
| `L_ss` | 22,98 m | 21,81 m | 23,07 m | **+5,8 %** |

**Tolerância adotada: < 10 %**, e é a que o próprio artigo declara ("os desvios foram
inferiores a 10 %"). A escolha automática do programa cai a no máximo um passo de grade
da escolha do artigo — testado.

---

## 5. Defeitos encontrados

**Nenhum defeito novo neste passo.** As quatro divergências já estavam identificadas,
argumentadas e testadas. O que a fase acrescentou foi a **verificação na fonte** de cada
uma, que antes se apoiava na descrição do código:

| afirmação do código | confirmada? | como |
|---|---|---|
| a Eq. (22) imprime `4,12×10⁴` | **sim** | página renderizada |
| a Tabela 3 implica `4,2004×10⁴` | **sim** | recalculado das seis linhas, dispersão ±0,02 % |
| a Eq. (21) divide `(h_w)max` por **β** | **sim** | página renderizada |
| a Figura 3 rotula o eixo `β = h_o/d` | **sim** | página renderizada — é o que sustenta a nota 3 |
| a Tabela 1 repete `1,1` e `0,6` nas duas colunas | **sim** | texto extraído |
| as Eq. (9)–(20), (23), (24) estão implementadas literalmente | **sim** | páginas renderizadas |

### A divergência 3 (Eq. 21) merece registro à parte

A forma publicada divide **as duas** espessuras máximas por β. Mas a Figura 3 do próprio
artigo rotula o eixo vertical **`β = h_o/d`** — a altura fracionária do **óleo** —, e num
vaso meio cheio a da água é `0,5 − β`. O texto sob as Eq. (19) e (21) descreve β como "a
altura fracionária do líquido", que contradiz o rótulo da sua própria figura.

Para o caso publicado (`β = 0,0685`, `(h_o)max = 1130,3 mm`, `(h_w)max = 1644,0 mm`):

| leitura | `d_max` |
|---|---|
| Eq. (19), água em óleo — `(h_o)max/β` | 16.508 mm |
| Eq. (21) **publicada** — `(h_w)max/β` | 24.011 mm |
| Eq. (21) **geométrica** — `(h_w)max/(0,5−β)` | **3.810 mm** |

A forma publicada infla o teto de óleo-em-água em `β/(0,5−β) ≈ 6,3×`, o que **inverte
qual mecanismo governa**. Sob a leitura geométrica o teto cai para 3.810 mm e **toda a
faixa da Tabela 3 (5200–5950 mm) seria recusada**.

**A implicação é séria e fica registrada:** o método publicado é **não-conservador
exatamente no mecanismo que ele descarta por argumento de tamanho de gotícula** (500 µm >
200 µm). O programa segue o publicado — é o propósito declarado, e mudá-lo faria o
caso-ouro deixar de reproduzir o artigo — mas emite `Eq. 21*` no rastro de cálculo, de
modo que o número apareça no memorial que vai anexo ao relatório em vez de viver só num
comentário de código. O teste verifica que **as duas linhas existem**, que a razão entre
elas é exatamente `β/(0,5−β)`, e que a publicada é mais de 6× a geométrica.

---

## 6. Lacunas não fechadas

1. **A Eq. (9) não tem faixa de validade declarada.** `C_D = 24/Re + 3/√Re + 0,34` é um
   ajuste que a literatura usa até `Re ~ 10⁵`, mas nem o artigo nem o livro declaram
   faixa. Não há o que verificar contra a fonte, e inventar um limite seria o oposto do
   critério desta fase. O que existe — e é o que a fonte de fato pede — é a convergência,
   e ela é verificada: `converge_drag` devolve `converged`, e `gas_capacity_dleff` recusa
   com mensagem nomeando `µ_g` quando ela falha.

2. **Stokes (Eq. 17/20) sem faixa declarada.** Mesma situação do tratador
   (`03-*.md` §6.3): a lei exige `Re` de gotícula ≲ 1 e nenhuma das duas fontes o declara.
   Candidato a linha diagnóstica do rastro; **decisão do usuário**.

3. **A Tabela 2 do artigo corresponde a uma iteração interrompida.** Reproduzi-la
   exatamente exige `C_D ≈ 1,25`, valor intermediário entre a 2ª e a 3ª iteração da
   substituição direta; o ponto fixo verdadeiro é `C_D ≈ 1,82` com `µ_g = 0,012 cP`. O
   programa converge de verdade. Como o bloco A não governa, a diferença não move o vaso —
   mas explica por que a Tabela 2 não é reproduzida linha a linha.

4. **AMBIGUIDADE HERDADA — `L_ss` (divergência 4).** O artigo usa a relação do bloco que
   governa; Stewart & Arnold §4.9.1 manda tomar o **maior** dos dois. As duas regras
   coincidem nas três primeiras linhas da Tabela 3 e divergem nas três últimas: em
   `d = 5950 mm` o artigo publica `L_ss = 19,64 m` contra `20,68 m` pela regra do livro —
   5 % curto, e `SR` 3,30 em vez de 3,48. **Não muda o vaso escolhido** (o ótimo continua
   em 5650 mm pelos dois critérios). Seguimos o artigo **aqui**, porque é o que reproduz a
   Tabela 3; o vaso bifásico e o tratador seguem o livro. Ver `03-*.md` §6.4 e `05-*.md`.

5. **Um só caso de validação.** O caso-ouro é a Tabela 3, e ele valida o caminho feliz de
   **um** separador trifásico. Um segundo caso de literatura — de preferência com
   geometria ou razão água/óleo bem diferente — é o que separa "reproduz o artigo que
   copiei" de "implementa o método". Está registrado como pendência do Sprint 11 em
   [SPRINTS.md](../../SPRINTS.md), e **continua aberto**.

### Erratas menores da fonte, sem consequência

- Sob a Eq. (15) o artigo troca os rótulos: chama `L_eff` de "Comprimento total" e `L_ss`
  de "comprimento efetivo de operação". As Eq. (23)/(24) e as Tabelas 3/4 usam a
  convenção correta.
- Sob a Eq. (22) o texto descreve `L_eff` como "o valor mínimo necessário para que ocorra
  a separação das fases líquida e gasosa" — descrição do bloco de gás aplicada ao bloco
  de líquido.
- A Tabela 1 lista "Peso Específico do Óleo = 0,9" ao lado de "Densidade do Óleo =
  863 kg/m³" (⇒ 0,863) e "°API = 32" (⇒ 0,865 pela Eq. 12).

---

## Resultado

| | |
|---|---|
| Testes do método | 77 + 33 (arrasto) + 18 (β) = **128** (inalterado) |
| Equações conferidas contra a fonte | **18** |
| Divergências fonte↔código | 4, todas **confirmadas na fonte** nesta fase |
| Defeitos encontrados | **0** |
| Caso-ouro | Tabela 3 (18 valores) a **+0,33…+0,46 %**, tolerância 0,5 % |
| Lacunas declaradas | 5 (faixa da Eq. 9, Stokes, Tabela 2, `L_ss`, segundo caso) |
