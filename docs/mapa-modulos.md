# Mapa dos módulos — o que existe, quem despacha o quê, e onde o memorial se encaixa

Auditoria do estado do programa no ponto em que o memorial de cálculo documental entrou.
Serve a duas perguntas: *onde ponho conteúdo novo de um equipamento?* e *o que eu ganho
de graça ao registrar um método?*

Regra que atravessa tudo: **o core é a fonte de verdade e roda headless.** `app/` depende
de `src/`, nunca o contrário — `test/architecture.jl` garante isso, e é por ela que a
camada documental entrou como dado/texto, sem dependência nova.

---

## 1. Os equipamentos registrados

`__init__` em [src/FPSOSiz.jl](../src/FPSOSiz.jl) registra sete pares
equipamento↔método; [config/catalogo.toml](../config/catalogo.toml) diz quais viram box
no menu.

| box (URL) | equipamento | método | família | fonte |
|---|---|---|---|---|
| `separador-3f` | `Separator` | `StewartArnold` | vaso | Alves & Komesu (2025) / S&A (2008) |
| `knockout-2f` | `KnockoutDrum` | `StewartArnoldTwoPhase` | vaso | S&A (2008), cap. 3 |
| `vaso-eletrostatico` | `ElectrostaticTreater` | `ArnoldElectrostatic` | vaso (cheio) | S&A (2008), §4.7–4.9 |
| `bomba-centrifuga` | `CentrifugalPump` | `MoranPumpSizing` | — | Moran (CEP, 2016) |
| `trocador-calor` | `ShellTubeExchanger` | `SaariLMTD` | — | Saari (LUT) + Bell-Delaware |
| `analise-pinch` | `PinchTarget` | `PinchKemp` | — (não dimensiona) | Kemp (2007), cap. 2–3 |
| `controle-separador` | `SeparadorDinamico` | `SongDinamico` | — (não dimensiona) | Song et al. (2023) |

Os dois últimos **não devolvem `SizingResult`**: a Análise Pinch dá alvos de energia de
uma rede, e o dinâmico simula no tempo. Os dois servem por caminhos próprios no app.

---

## 2. O contrato método ↔ motor

Declarado em [src/engine/contract.jl](../src/engine/contract.jl). A forma que todo
dimensionamento tem:

```
para cada x da grade:
    y(x) = max sobre os casos de  requirement(m, x, restrições)
    d(x) = derived(m, x, y, …)
    admissível se x ≤ ceiling ∧ case_admissible ∧ admissible
escolhe-se o x admissível que minimiza objective(…)
```

| hook | quem despacha | default | serve a |
|---|---|---|---|
| `parameters` | método | — | formulário |
| `case_input` | método | `StreamState` | física |
| `sweep_axis` | método | — | cursor, eixo x |
| `sizing_constraints` | método | — | **os números e o rastro** |
| `requirement` / `governing_of` / `ceiling_of` | **as restrições** | vaso em `constraints.jl` | motor |
| `derived` / `admissible` / `objective` | método | — | motor |
| `result_fields` | método | — | **cartão, `.txt`, memorial** |
| `sweep_columns` | método | — | tabela, CSV |
| `trace_blocks` | método | ordem de aparição | painel de memorial |
| `method_reference` | TOML do método | `""` | cabeçalho do `.txt` |
| `slenderness_equation` | método | `"—"` | linha da seleção no rastro |
| `cross_section` | método | vazio | desenho, camadas de fase |
| **`memorial_spec`** | **método** | **`nothing`** | **documento A4** |

`requirement`/`governing_of`/`ceiling_of` despacham no **tipo das restrições**, não no do
método: quem produzir um `VesselConstraints` ganha varredura, `Lss`, esbeltez, banda e
teto sem declarar nada. Foi assim que o vaso bifásico nasceu com nove linhas de física.

---

## 3. As três saídas do mesmo cálculo

O ponto que o memorial documental explora: **três artefatos, uma física**.

| artefato | o que mostra | de onde sai | onde |
|---|---|---|---|
| Cartão da tela | resultado no ponto do cursor | `result_fields(m, alvo_cartao(st))` | `api.jl` |
| Memorial `.txt` | rastro de **todos** os cantos, em colunas fixas | `CalcTrace` + `linha_memorial` | `report.jl` |
| Memorial A4 | equação, variável, premissa, hipótese, verificação | `MemorialSpec` + `CalcTrace` + `result_fields` | `memorial/` |

Nenhum dos três recalcula nada. O cartão e o documento chamam **a mesma função**
(`campos_resultado`), o que torna a divergência entre tela e PDF impossível por
construção — e não por comparação.

---

## 4. A camada documental (nova)

```
src/memorial.jl                      contrato: MemorialSpec + os cinco descritores
src/memorial_specs/stewart_arnold.jl conteúdo do separador trifásico
app/src/memorial/documento.jl        folha A4, bloco de título, tokens, paginação
app/src/memorial/folhas.jl           rosto · premissas · fórmulas · resultados · figuras
app/public/memorial.css              geometria e tipografia de impressão
```

**Infra compartilhada, conteúdo específico.** `documento.jl` e `folhas.jl` não sabem o
que é um separador: trocar o `MemorialSpec` troca o documento inteiro. Acrescentar o
memorial de um equipamento é escrever um `memorial_spec(::SeuMetodo)` — nenhuma linha de
`app/`.

Posição no `FPSOSiz.jl`: `memorial.jl` entra depois de `types/results.jl` (precisa de
`CalcTrace`) e antes de `config.jl`; cada `memorial_specs/*.jl` entra logo depois do
arquivo do seu método.

---

## 5. O app

| arquivo | papel |
|---|---|
| `state.jl` | `AppState` — um por box, sob trava; casos, globais, cursor, resultado |
| `api.jl` | estado ↔ JSON; `esquema`, `cartao`, `tabela`, `memorial` (rastro), `estado` |
| `report.jl` | exportação: CSV da varredura, memorial `.txt`, SVG das figuras |
| `desenho/` | `geometria.jl` + `vaso.jl` (elevação, corte), `graficos.jl` (envelope, banda), `linha.jl` (bomba, trocador) |
| `desenho/figuras.jl` | qual figura vai em qual área — despacha no método |
| `memorial/` | o documento A4 |
| `server.jl` | rotas, trava, conferência de origem, subida |
| `dinamico.jl` | o subapp do separador dinâmico (não passa por `AppState`) |

### Rotas

| rota | verbo | devolve |
|---|---|---|
| `/` | GET | menu (catálogo) |
| `/app/:box` | GET | tela de dimensionamento (ou a dinâmica) |
| **`/app/:box/memorial`** | **GET** | **documento A4 imprimível** |
| `/api/:box/esquema` | GET | descritores do formulário |
| `/api/:box/estado` | GET | fotografia completa |
| `/api/:box/memorial` | GET | rastro agrupado por bloco (painel da tela) |
| `/api/:box/dimensionar` | POST | aplica o formulário e dimensiona |
| `/api/:box/desenho` | POST | move o cursor; devolve figuras, cartão e tabela |
| `/api/:box/casos/{arquivos,abrir,salvar}` | GET/POST | conjuntos de casos |
| `/api/:box/exportar` | POST | CSV + `.txt` + SVG |
| `/api/:box/simular` | POST | só o box dinâmico |
| `/api/parar` | POST | encerra |

`/app/:box/memorial` e `/api/:box/memorial` são **artefatos diferentes sobre o mesmo
cálculo**: o primeiro é o documento assinável, o segundo é o rastro que o painel da tela
abre para consulta.

---

## 6. Onde pôr coisa nova

| quero… | escrevo em |
|---|---|
| um parâmetro novo | `config/equipment/<eq>/<metodo>.toml` — a tela monta sozinha |
| uma constante de correlação | o mesmo TOML, em `[constants]` |
| um equipamento novo | `src/sizing/<eq>/`, `register!` no `__init__`, box no `catalogo.toml` |
| uma figura nova | `figuras(::MeuMetodo, st)` em `desenho/figuras.jl` |
| um campo no cartão | `result_fields(::MeuMetodo, r)` |
| um bloco no rastro | `trace!` dentro de `sizing_constraints` + `trace_blocks` |
| **o memorial de um equipamento** | **`memorial_spec(::MeuMetodo)`** |
| algo na folha A4 para todos | `app/src/memorial/documento.jl` ou `folhas.jl` |

Nunca em `app/public/index.html` nem em `app.js`: a tela não cita parâmetro nem grandeza
pelo nome, e `app/smoke.jl` tem duas guardas que quebram se alguém tentar.

---

## 7. Guardas que protegem tudo isto

| guarda | arquivo | o que impede |
|---|---|---|
| headless | `test/architecture.jl` | o core citar GUI; dependência nova |
| casos-ouro | `test/golden_*.jl` | mudar a física sem notar |
| bijeção equação↔rastro | `test/memorial.jl` | documentar conta que não se faz, e vice-versa |
| sem número na camada documental | `test/memorial.jl` (`fieldtypes`) | uma segunda fonte para o mesmo valor |
| vocabulário da tela | `app/smoke.jl` | a interface citar uma grandeza pelo nome |
| ids HTML ↔ JS | `app/smoke.jl` | a tela parar em "Carregando…" |
| paleta CSS ↔ Julia | `app/smoke.jl` | cor da legenda divergir da do desenho |
| grade do memorial CSS ↔ Julia | `app/smoke.jl` | colunas do documento fora da banda do handoff |
| tela ↔ documento | `app/smoke.jl` | o PDF mostrar um vaso e a tela, outro |
