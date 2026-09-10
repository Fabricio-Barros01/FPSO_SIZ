# Passo 3 — Tratador eletrostático horizontal

**Método:** `:arnold_electrostatic` · **Equipamento:** `:treater`
**Fonte:** Stewart, M. & Arnold, K., *Gas-Liquid and Liquid-Liquid Separators*,
Gulf Professional Publishing/Elsevier, 2008 — cap. 4 §4.7 a §4.9.6, pp. 148–161.
**228 páginas, PDF não cifrado, texto extraível.**
**Arquivos:** [electrostatic.jl](../../src/sizing/treater/electrostatic.jl),
[beta.jl](../../src/sizing/separator/beta.jl),
[electrostatic.toml](../../config/equipment/treater/electrostatic.toml)

É o vaso mais simples dos três (sem bloco de gás) e o único **sem caso-ouro** — o que faz
dele o método cuja validação depende inteiramente de coerência interna da fonte.

---

## 1. Equação do código × equação da referência

| # | Página | Forma publicada | Código | Veredito |
|---|---|---|---|---|
| Eq. (4.5b) | p. 152 | `h_o = **0,0033**·(tr)o(ΔSG)d_m²/µ` | [electrostatic.jl:171](../../src/sizing/treater/electrostatic.jl#L171) usa **0,033** | **divergente** — divergência 1 |
| Eq. (4.5a) | p. 152 | campo: `h_o = 0,00128·(tr)o(ΔSG)d_m²/µ` | — (referência de conferência) | consistente com 0,033; ver §2.1 |
| Eq. (4.6b) | p. 152 | `(h_o)max = 8250·(tr)o(ΔSG)/µ` para `d_m = 500 µm` | — (referência de conferência) | **confirma 0,033**: `0,033×500² = 8250` exato |
| Eq. (4.6a) | p. 152 | campo: `(h_o)max = 320·(tr)o(ΔSG)/µ` | — | `320 in × 25,4 = 8128 mm`, −1,48 % de 8250 |
| Eq. (4.9b) | p. 154 | `(h_w)max = **1520**·(tr)w(ΔSG)/µ_w` para `d_m = 200 µm` | [:172](../../src/sizing/treater/electrostatic.jl#L172) usa a forma geral ⇒ **1320** | **divergente** — divergência 2 |
| Eq. (4.9a) | p. 154 | campo: `(h_w)max = 51,2·(tr)w(ΔSG)/µ_w` | — | `51,2 in × 25,4 = 1300,5 mm`, −1,48 % de 1320 |
| Eq. (4.15b) | p. 160 | `d²L_eff = 21.000·[(tr)o·Qo + (tr)w·Qw]/α` | [:204](../../src/sizing/treater/electrostatic.jl#L204) | **equivalente** — literal |
| Eq. (4.16) | p. 160 | `a_w = a_l·Qw(tr)w / [Qo(tr)o + Qw(tr)w]` | [:176](../../src/sizing/treater/electrostatic.jl#L176) | **equivalente** — literal, com `a_l = α` |
| Eq. (4.17) | p. 160 | `a_w = (1/180)cos⁻¹[1−2β_w] − (1/π)[1−2β_w]√(…)`, "solving by trial and error" | [beta.jl:54](../../src/sizing/separator/beta.jl#L54) `segment_height_fraction` | **equivalente após rearranjo** — ver §2.3 |
| Eq. (4.18) | p. 160 | `d_max = (h_o)max/(β_l − β_w)` | [:192](../../src/sizing/treater/electrostatic.jl#L192) | **equivalente** — literal |
| — | p. 160 | **não existe** contraparte de óleo-em-água para o vaso não meio cheio | [:193](../../src/sizing/treater/electrostatic.jl#L193) `d_max_oiw = (h_w)max/β_w` | **acréscimo declarado** — divergência 3 |
| Eq. (4.11)/(4.12b) | p. 154–155 | `Lss = (4/3)L_eff` e `Lss = L_eff + d/1000`, "the larger of the following" | [:226](../../src/sizing/treater/electrostatic.jl#L226) `max(…)` | **ambíguo na fonte** — ver §6 |
| Eq. (4.13) | p. 155 | `Lss = (4/3)L_eff`, "should not exceed" para vaso de capacidade de **líquido** | não aplicado como teto | **ambíguo na fonte** — ver §6 |
| §4.9.2 | p. 155 | esbeltez entre **3 e 5** | `sr_min = 3`, `sr_max = 5`, `sr_target = 4` | **equivalente** |
| §4.7.2 | p. 149 | gotícula sem tratamento: **500 µm** | `untreated_droplet_um = 500` | **equivalente** — usada só como base de comparação |

### Divergências

| # | O que a fonte imprime | O que o código faz | Como foi decidido |
|---|---|---|---|
| 1 | Eq. (4.5b): `0,0033` | `0,033` | **O livro se contradiz num fator de 10.** O §4.9.3 passo 3, quatro páginas adiante, imprime `0,033` para a mesma equação. Três conferências independentes apontam para `0,033` — ver §2.1. **Checável por dentro** |
| 2 | Eq. (4.9b): `1520` | forma geral ⇒ `1320` | `0,033 × 200² = 1320`; a conversão exata da Eq. (4.9a) de campo dá `51,2 × 25,4 = 1300,5`, que fica a **−1,48 %** de 1320 — exatamente o mesmo desvio que o par (4.6a)/(4.6b) tem entre si. Contra 1520 o erro seria −14,4 %. **Checável por dentro** |
| 3 | §4.9.6 só publica a Eq. (4.18), água-em-óleo | acrescenta `d_max = (h_w)max/β_w` | O livro generaliza a Eq. (4.8) do vaso meio cheio para a (4.18), mas **não escreve** a contraparte da Eq. (4.10). Aqui ela é a geométrica — espessura de água sobre a fração de altura que a água ocupa — e governa **quando for menor**. Leitura conservadora, e deliberadamente oposta à decisão do separador trifásico (ver `04-*.md`, nota 3), porque lá havia uma tabela publicada a reproduzir e aqui não há |

---

## 2. Auditoria dimensional

### 2.1 O `0,033` da Eq. (4.5b) — derivado das unidades, e é ele que decide a divergência 1

A espessura é velocidade de Stokes × tempo de retenção:

```
v = g·Δρ·d²/(18·µ)                 [m/s]
h = v·t                            [m]
```

com `d_m` em µm (`×10⁻⁶` m), `t` em min (`×60` s), `µ` em cP (`×10⁻³` Pa·s),
`Δρ = ΔSG × 1000` kg/m³, e `h` pedido em mm (`×1000`):

```
coef = 9,81 · 1000 · (10⁻⁶)² · 60 / (18 · 10⁻³) · 1000
     = 0,0327   mm·cP / (min·µm²)
```

| candidato | desvio contra a derivação |
|---|---|
| **`0,033`** (§4.9.3 passo 3, e o que o código usa) | **+0,92 %** |
| `0,0033` (Eq. 4.5b como impressa) | **−89,9 %** — um fator de 10 |

Os +0,92 % são o arredondamento de dois algarismos do próprio livro. **A auditoria
dimensional sozinha resolve a contradição da fonte**, sem recorrer a nenhuma outra
referência — e é o padrão mais forte que qualquer coeficiente deste projeto atingiu.

Três conferências independentes concordam:

| conferência | resultado |
|---|---|
| derivação de unidades a partir de Stokes | **0,0327** — o `0,033` está a +0,9 % |
| Eq. (4.6b) do próprio livro (`d_m = 500 µm ⇒ 8250`) | `0,033 × 500² = 8250` **exato** |
| conversão exata da Eq. (4.6a) de campo (`320 in`) | `8128 mm`, −1,48 % de 8250 |

### 2.2 O `21.000` da Eq. (4.15b)

| conferência | resultado |
|---|---|
| Eq. (4.15b) com `α = 0,5` tem de reproduzir a Eq. (4.4b) do vaso meio cheio | `21000/0,5 = 42000` = `4,2×10⁴` **exato** |
| conversão exata da forma de campo (`1,42`, Eq. 4.4a) | `42152,1` — o publicado fica a **−0,36 %** |

**Segue-se o publicado.** Não há contradição interna a resolver, e 0,36 % não é
contradição. É o contraste deliberado com a Eq. 22 do separador trifásico, onde o valor
impresso erra 1,9 % contra a **tabela do próprio artigo** e por isso é derivado.

### 2.3 Eq. (4.17) — o `1/180` é o arco-cosseno em graus

A fonte imprime `a_w = (1/180)cos⁻¹[1−2β_w] − (1/π)[1−2β_w]√(…)` e manda resolver "by
trial and error". A mistura de `1/180` com `1/π` na mesma expressão não é erro: o
primeiro termo tem o arco-cosseno em **graus** e o segundo em radianos. Com
`arccos_graus = arccos_rad · 180/π`, `(1/180)·arccos_graus = (1/π)·arccos_rad`, e a
expressão vira a fração de área do segmento circular:

```
a(β) = (1/π)·[arccos(1−2β) − 2(1−2β)√(β(1−β))]
```

`segment_height_fraction` inverte **essa** relação por bisseção (80 passos ⇒ ~10⁻²⁴ em
`u`), o que é exato e não depende de ler figura nem de convergir tentativa e erro. O teste
confere que ela é a inversa da área à precisão de 10⁻⁹, que é monótona, e que é simétrica
em torno do meio.

### 2.4 Unidades de entrada, constante e saída

| grandeza | unidade | onde converte |
|---|---|---|
| `Q_o`, `Q_w` | m³/h | `field_units` — **uma vez** |
| `µ_o`, `µ_w` | cP | `field_units` — **uma vez** |
| `SG_o`, `SG_w` | adimensional | `field_units` (`ρ/1000`) |
| `(tr)_o`, `(tr)_w` | min | TOML, sem conversão |
| `d_m` (água, óleo) | µm | TOML, sem conversão |
| `0,033` | mm·cP/(min·µm²) | — (a constante **é** a conversão; §2.1) |
| `21.000` | mm²·m·h/(min·m³) | — |
| `(h_o)max`, `(h_w)max`, `d_max` | **mm** | saída direta da correlação |
| `d²L_eff` | mm²·m | saída |
| `L_ss` | m | `d/1000` converte o mm do diâmetro |

**Coerência do bloco B verificada:** `[mm·cP/(min·µm²)] · [min] · [–] · [µm²] / [cP] = mm` ✓.
**Bloco C:** `[mm²·m·h/(min·m³)] · [min] · [m³/h] = mm²·m` ✓, e `d²·L_eff / d² = L_eff` em
metros com `d` em mm ✓.

Nenhuma conversão dupla e nenhuma ausente: este método **não** toca `Units` fora de
`field_units`, e as duas únicas divisões por 1000 no arquivo são o `d/1000` de `L_ss`
(Eq. 4.12b) e o `β_w = 1 − β_o` de `cross_section`, que não é conversão.

---

## 3. Limites de validade: declarados × verificados

| limite | declarado pela fonte | verificado no código | veredito |
|---|---|---|---|
| **Stokes (`Re` de gotícula)** | **não declarado** pelo livro; a lei exige `Re ≲ 1` | **não verificado** | **lacuna** — ver §6, com o número medido |
| esbeltez | §4.9.2: **3 a 5** | `sr_min`/`sr_max` em `admissible` | **verificado** |
| `α` (fração líquida) | §4.9.6 trata `α` genérico; o tratador opera cheio | **constante = 1**, não parâmetro | **verificado, e deliberadamente fechado** — ver abaixo |
| `d_m` sem tratamento | §4.7.2: 500 µm | constante de comparação, emitida no rastro | **verificado** |
| ΔSG > 0 | implícito | checado, com mensagem própria | **verificado** |
| `β_o = β_l − β_w > 0` | implícito | checado, com mensagem própria | **verificado** |
| campo elétrico → `d_m` | **a fonte não fecha** | `d_m` é entrada do usuário | **lacuna declarada** — ver §5 |

**`α = 1` é constante e não parâmetro, e isso é uma trava de validade.** Com `α < 1`
existe fase gasosa, e com fase gasosa existe o bloco A (Eq. 4.14b) que este método **não
avalia**. Expor `α` no formulário convidaria a pôr 0,7 e receber um vaso dimensionado
ignorando uma restrição que se aplica — silenciosamente. Está argumentado no TOML e é a
decisão certa: quem precisa de vaso parcialmente cheio usa o separador trifásico.

---

## 4. Casos-ouro

**Não há.** É a declaração central deste passo, e não uma omissão.

O livro traz procedimento (§4.9.3) e exemplos para o separador trifásico **meio cheio**,
não para o tratador eletrostático. O §4.9.4–4.9.6, que é a generalização para `α ≠ 0,5` e
a base deste método, **não tem exemplo numérico**. Não existe tabela publicada a
reproduzir, como a Tabela 3 de Alves & Komesu ou a Tabela 3.4 do cap. 3.

O que ancora o método, na falta disso:

| âncora | força |
|---|---|
| `0,033` derivado das unidades (§2.1) | **forte** — resolve a contradição da fonte sem outra referência |
| `0,033` reproduzindo a Eq. (4.6b) do livro | **forte** — exato |
| `21000/α` reproduzindo a Eq. (4.4b) com `α = 0,5` | **forte** — exato |
| `1320` fechando com a Eq. (4.9a) de campo no mesmo −1,48 % do outro par | **forte** |
| `segment_height_fraction` como inversa exata da área do segmento | **forte** — 10⁻⁹ |
| `β` do vaso meio cheio continuando a bater com a Figura 3 (`test/beta.jl`) | média — é o caso particular |
| o mesmo `0,033` que Alves & Komesu usam desde o Sprint 1 | média — fonte secundária que reproduz esta |

**Tolerâncias adotadas:** as conferências de coeficiente são exatas (`==`) ou de 10⁻⁹,
porque comparam número publicado com número publicado. As duas comparações contra
conversão de unidade de campo usam `rtol = 0,02`, justificado pelo arredondamento de dois
a três algarismos do livro (`320`, `51,2`, `8250`, `1520`): o desvio real medido é 1,48 %
nas duas, e é o mesmo nas duas, o que é ele próprio a evidência de que a diferença é
arredondamento sistemático e não erro.

---

## 5. Defeitos encontrados

**Nenhum defeito novo neste passo.** As três divergências de fonte já estavam
identificadas, argumentadas e testadas antes desta fase; o que a fase acrescentou foi a
**derivação dimensional independente** do `0,033` (§2.1), que eleva a decisão de "o livro
se contradiz e escolhemos a versão que fecha com as outras equações dele" para "a análise
dimensional dá 0,0327, e o `0,033` está a 0,9 % dela".

Confirmado nesta fase, lendo a fonte:

- a Eq. (4.5b) **imprime mesmo** `0,0033`, e o §4.9.3 imprime `0,033` — a contradição é real;
- a Eq. (4.9b) **imprime mesmo** `1520`;
- o §4.9.6 **de fato não publica** a contraparte de óleo-em-água, e o `d_max = (h_w)max/β_w`
  do código é acréscimo, não transcrição;
- a Eq. (4.15b) imprime `21.000` e a (4.16) e a (4.18) estão implementadas literalmente.

---

## 6. Lacunas não fechadas e ambiguidades da fonte

1. **Não há caso-ouro** (§4). É a lacuna estrutural do método.

2. **A referência não fecha o campo elétrico.** *Gas-Liquid and Liquid-Liquid Separators*
   cita tratadores eletrostáticos quatro vezes, todas de passagem, e remete o
   dimensionamento do campo (gradiente de tensão, espaçamento e área de eletrodo, consumo
   do transformador) ao volume *Emulsions and Oil Treating*, **que não está em
   `References/`**. Sem ele não há correlação que ligue tensão e espaçamento ao diâmetro
   coalescido. `d_m` é entrada do usuário, e o rastro emite o ganho `(d_m/500)²` que a
   hipótese vale — que é a única forma honesta de a premissa aparecer quantificada no
   memorial. O programa **não** dimensiona eletrodo, fonte, nem prevê coalescência a
   partir da tensão, e não finge fazê-lo.

3. **Limite de Stokes não verificado.** A lei de Stokes exige `Re` de gotícula ≲ 1, e o
   livro não declara a faixa. Medido no ponto que o método escolhe com os defaults:

   | mecanismo | `d_m` | `µ` da fase contínua | `v` de Stokes | **`Re` de gotícula** |
   |---|---|---|---|---|
   | água em óleo | 1000 µm | 10,0 cP | 7,47×10⁻³ m/s | **0,64** |
   | óleo em água | 200 µm | 1,10 cP | 2,72×10⁻³ m/s | **0,49** |

   **Os dois estão dentro** — Stokes vale no caso default. Mas nada verifica isso: com
   água menos viscosa ou gotícula maior o `Re` passa de 1 e a correlação é extrapolada em
   silêncio. **Não foi transformado em critério de recusa** porque o critério desta fase é
   recusar fora de faixa *declarada pela fonte*, e esta não é declarada por fonte nenhuma
   do projeto — a mesma razão pela qual o piso de `F` do trocador ficou de fora. Emitir o
   `Re` da gotícula como linha diagnóstica do rastro é o passo seguinte natural, e é
   decisão do usuário.

4. **AMBIGUIDADE DA FONTE — RESOLVIDA NO PASSO 5.** O §4.9.1 tem dois parágrafos com
   regras diferentes:

   - para vasos dimensionados por **capacidade de gás**: *"the seam-to-seam length of a
     vessel may be estimated as **the larger of the following**"* — Eq. (4.11)
     `Lss = (4/3)L_eff` e Eq. (4.12b) `Lss = L_eff + d/1000`;
   - para vasos dimensionados por **capacidade de líquido**: *"The seam-to-seam length
     **should not exceed** the following"* — Eq. (4.13) `Lss = (4/3)L_eff`.

   O tratador é **sempre** de capacidade de líquido (não tem bloco de gás), e
   `lss_from` aplica o `max(…)` incondicional — que pode **passar** do teto da Eq. (4.13)
   quando `d/1000 > L_eff/3`.

   Alcance medido na grade dos defaults: as três últimas linhas (`d ≥ 3300 mm`) excedem o
   teto; as dezesseis primeiras, não. **O diâmetro escolhido (3150 mm) fica exatamente
   dentro** — ali `(4/3)L_eff = 12,885 m` governa contra `L_eff + d/1000 = 12,813 m` —,
   então **o vaso do caso default não muda** sob nenhuma das duas leituras. É latente, não
   ativo.

   **A Tabela 3.4 do próprio livro resolve a favor do `max`.** O §3.8.4 do cap. 3 é
   palavra por palavra o mesmo texto, e o Exemplo 3.2 que o acompanha traz um vaso
   **governado por líquido** cujo `L_ss` publicado **excede** `(4/3)L_eff` nas três
   últimas linhas, com a nota de rodapé dizendo explicitamente "`L_ss = L_eff + 2,5`
   governs". Ou seja: o livro, no seu próprio exemplo resolvido, toma o maior dos dois
   mesmo num vaso de capacidade de líquido. A leitura "teto" fica descartada.

   **Não há decisão de engenharia a tomar, e o código já está certo.** Ver
   `05-vaso-flash-knockout.md` §5, com a tabela linha a linha.

---

## Resultado

| | |
|---|---|
| Testes do método | 120 (inalterado — nenhum defeito novo a fixar) |
| Equações conferidas contra a fonte | **14** |
| Divergências fonte↔código | 3, todas já documentadas e agora **confirmadas na fonte** |
| Conferência nova desta fase | derivação dimensional do `0,033` (§2.1) |
| Defeitos encontrados | **0** |
| Ambiguidades da fonte | 1 (`Lss`, §6.4) — **resolvida no passo 5, a favor do código** |
| Lacunas declaradas | 3 (caso-ouro, campo elétrico, `Re` de Stokes) |
