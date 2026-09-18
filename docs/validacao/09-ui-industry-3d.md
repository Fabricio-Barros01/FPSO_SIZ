# Passo 9 — Design system "Industry" e visor 3D (fecho da fatia SEP)

**Módulo:** camada de tela · **Não toca em física.** Nenhuma equação, referência ou
número mudou.
**Fonte:** handoff de design `References/FPSO SIZ UI mockups/` — design system
`_ds/industry-2705f781-…/`, artboards `.dc.html`, `viewer3d.js`, `models/*.js`.
**Arquivos:** [app/public/ds/styles.css](../../app/public/ds/styles.css),
[app/public/vendor/](../../app/public/vendor/),
[app/public/viewer3d.js](../../app/public/viewer3d.js),
[app/public/models/separador.js](../../app/public/models/separador.js),
[app/src/desenho/figuras.jl](../../app/src/desenho/figuras.jl),
[app/src/formato.jl](../../app/src/formato.jl).

Fecha o que o plano §3 pedia para a fatia do separador e que o
[passo 8](08-memorial.md) não entregou: o design system aplicado e o visor 3D dirigido
pela geometria calculada.

---

## 1. O que foi vendorizado, e por que vendorizado

| arquivo | origem | licença |
|---|---|---|
| `ds/styles.css` | `_ds/industry-…/styles.css` do handoff | nosso |
| `ds/fonts/*.woff2` (10) | Google Fonts — Barlow, Barlow Condensed, subsets `latin` e `latin-ext` | SIL OFL 1.1 |
| `vendor/three.module.min.js` | jsDelivr, three@**0.169.0** | MIT |
| `vendor/three-addons/controls/OrbitControls.js` | idem | MIT |
| `viewer3d.js`, `models/{separador,bomba,trocador}.js` | handoff | nosso |

**Tudo local, e essa é a exigência dura.** O programa é empacotado com PackageCompiler e
abre sem internet. Um `@import` do Google Fonts ou um `three` de CDN **não falha com
erro**: a tela abre com a fonte de sistema, ou o visor simplesmente não monta, e não há
nada no console que diga por quê. É a mesma razão pela qual `Genie.Assets` está fora
deste projeto — ver a nota no topo de `app/src/server.jl`.

A única alteração ao CSS do handoff foi trocar o `@import` remoto por dez `@font-face`
locais. `app/smoke.jl` confere, sobre o arquivo **sem comentários**, que não sobrou
nenhuma URL remota e que cada `url(fonts/…)` aponta para um arquivo que existe.

A versão do Three é fixada: a API de `OrbitControls` muda de forma entre versões, e
atualizar é trocar os dois arquivos juntos.

---

## 2. Duas paletas, e a distinção é deliberada

| paleta | de onde vem | por quê |
|---|---|---|
| **Chrome** — `FUNDO`, `TINTA`, `TINTA_FRACA`, `LINHA`, `DESTAQUE` | tokens do DS | a figura e a página em volta não podem ficar em dois azuis diferentes |
| **Fases** — `GAS`, `OLEO`, `AGUA` (+ `_ZONA`) | inalteradas | o "Industry" é mono em azul-aço; recolorir óleo e água nele apagaria a única coisa que essas cores dizem |
| **Status** — `OK`, `ALERTA`, `ERRO` | inalteradas | verde/vermelho significam aprovado/reprovado, não decoração |

Valores de chrome adotados:

| constante | antes | agora | token |
|---|---|---|---|
| `FUNDO` | `#f9f9f8` | `#f2f2f3` | `--color-bg` |
| `TINTA` | `#212327` | `#1d1f20` | `--color-text` |
| `TINTA_FRACA` | `#6b717a` | `#5d5d60` | `--color-neutral-700` |
| `LINHA` | `#d6d8db` | `#d4d4d7` | `--color-neutral-300` |
| `DESTAQUE` | `#1e4fa0` | `#416180` | `--color-accent-700` |

`DESTAQUE` é o passo **700** da rampa, não o acento base: o próprio guia do sistema manda
usar um passo profundo para texto em corpo de parágrafo, porque o acento base contra este
fundo dá ~3:1 — suficiente para ícone e chrome, não para número que se lê.

A duplicação `formato.jl` ↔ `app.css` continua vigiada pelo teste que já existia.

---

## 3. O visor 3D — melhoria progressiva, literalmente

A elevação SVG **continua sendo a figura**: é ela que carrega as cotas e é ela que vai
para o memorial impresso. O 3D é uma segunda vista da **mesma** geometria.

```
geometry_from(resultado, cursor, camadas, beta)
        │
        ├──► svg_elevacao(g)              a figura, com cotas  (sempre)
        └──► atributos_3d(m, g, camadas)  o modelo             (quando há WebGL)
```

Nenhum recálculo: os dois leem a mesma `geometry_from`. O smoke compara atributo por
atributo (`d`, `lss`, `leff`, `beta`) contra ela.

**`nivel` sai das `PhaseLayer` que o método declara**, como 1 menos a fração de gás — e
não de um `0,5` escrito à mão. Era exatamente essa dedução ("vaso meio cheio") que punha
metade de céu de gás num tratador cheio de líquido, e que `cross_section` nasceu para
corrigir; repeti-la no visor reintroduziria o defeito em três dimensões. O teste fixa
`nivel = 0,5` no separador e `nivel = 1,0` no tratador.

### Por que não pode ser dependência

1. **WebGL não existe em toda máquina.** Este programa trocou GLMakie por navegador
   porque uma VM sem OpenGL 3.3 derrubava o programa *antes da física*. Depender de WebGL
   desfaria metade dessa decisão.
2. O smoke roda headless, sem navegador.
3. São 690 kB que não têm por que ser baixados por quem nunca abriu a vista 3D — daí o
   `import()` dinâmico em vez de uma tag de script.

O botão "Ver 3D" **só aparece** quando o método declara modelo *e* `temWebGL()` responde
que sim. Falha ao carregar vira mensagem na barra de status e a figura fica em 2D.

### Onde o visor mora, e por que não em `area-principal`

Em contêiner próprio (`#area-3d`). `aplicarDesenho` troca os filhos de `area-principal` a
cada movimento do cursor; um `<fpso-3d>` ali dentro seria desconectado e reconectado a
cada troca — reinicializando o contexto WebGL inteiro dezenas de vezes por arrasto. Fora
dele, mover o cursor só reescreve atributos.

### Quem tem modelo

| método | modelo | por quê |
|---|---|---|
| `StewartArnold` | `separador` | conferido |
| `StewartArnoldTwoPhase` | `knockout` | conferido |
| `ArnoldElectrostatic` | `tratador` | conferido |
| `MoranPumpSizing`, `SaariLMTD`, `PinchKemp` | — | têm arquivo no handoff, **não conferidos** contra o desenho deles |

`modelo_3d` devolve `""` para os três últimos. Prometer um 3D que ninguém validou é pior
que não oferecê-lo — a mesma regra do `memorial_spec` no passo 8.

> **Atualizado em §6.1.** A bomba e o trocador foram conferidos e ligados; a Análise
> Pinch continua sem modelo, por não dimensionar equipamento nenhum.

### A tela não nomeia nenhuma grandeza

Os atributos chegam do servidor como dicionário e são repassados em laço
(`for (const [k, v] of Object.entries(...))`). `app.js` nunca escreve `lss` nem `leff` —
quem sabe que um vaso tem β é `atributos_3d`, em `figuras.jl`. A guarda de vocabulário do
smoke continua verde.

---

## 4. Verificação

```sh
julia --project=.   test/runtests.jl     # 4039 passam, 4 broken (pré-existentes)
julia --project=app app/smoke.jl         # 3034 passam
```

Guardas novas (todas em `app/smoke.jl`):

| guarda | o que impede |
|---|---|
| DS sem URL remota, `@font-face` apontando para arquivo existente | a tela abrir sem a fonte, offline, em silêncio |
| mapa de importação local, sem CDN | o visor não montar na máquina de quem recebe o programa |
| `viewer3d.js` e `models/*` só importam `three`/relativo | idem, mas por dentro do módulo |
| atributos 3D ≡ `geometry_from` | o 3D e a elevação mostrarem vasos diferentes |
| `nivel` do tratador = 1,0 | céu de gás num vaso cheio de líquido |
| `modelo_3d` vazio para bomba/trocador/pinch (→ só pinch, a partir de §6.1) | oferecer 3D não conferido |
| rotas servem DS, fontes, three, viewer, modelo | 404 silencioso num asset |

### Verificado no navegador, aqui

Com o servidor no ar e Firefox headless:

* a tela de dimensionamento monta com o design system — Barlow Condensed nos títulos,
  marcas de registro nos cantos, o primário como único objeto sólido — e o caso-ouro
  aparece correto (6300 mm · 18,59 m · 24,78 m · SR 3,93);
* o payload de `/api/separador-3f/desenho` traz
  `modelo3d = {separador, d 6.3, lss 24.78, leff 18.59, beta 0.0337, nivel 0.5}`;
* o visor monta: `webgl2 true`, `three r169`, elemento `fpso-3d` registrado,
  **canvas 900×500 criado, 20 malhas na cena**.

**O que não dá para verificar aqui:** a aparência do 3D. O `--screenshot` do Firefox
captura antes do primeiro `requestAnimationFrame` e não compõe WebGL em software, então o
quadro sai branco mesmo com a cena construída. A conferência visual é no navegador do
usuário.

---

## 5. Lacunas declaradas

| # | lacuna | encaminhamento |
|---|---|---|
| ~~1~~ | ~~Bomba e trocador não têm modelo 3D ligado~~ | **fechada** — ver §6.1 |
| ~~2~~ | ~~O layout das três colunas é o anterior; os artboards por box não foram replicados~~ | **fechada, e o enunciado estava torto** — ver §6.2 |
| ~~3~~ | ~~A página de menu não seguiu o artboard~~ | **fechada** — e havia um defeito real atrás dela; ver §6.3 |
| ~~4~~ | ~~Ícones Lucide (o DS pede stroke 1.5) não foram adotados~~ | **fechada em parte, e o resto recusado** — ver §6.4 |
| 5 | O memorial A4 **não** usa o DS, de propósito | é documento formal com tipografia própria (Arial/Times), especificada no handoff do memorial |
| 6 | `three.module.min.js` são 690 kB no repositório | é o custo de abrir offline; carregado só sob demanda |

---

## 6. A passagem dos artboards

Comparação tela a tela contra `References/FPSO SIZ UI mockups/*.dc.html`, com o servidor
no ar. O que se segue é o que mudou e o que deliberadamente não mudou.

### 6.1 Bomba e trocador ganharam o visor 3D

A lacuna dizia "conferir e ligar", e a conferência é o ponto. Os dois modelos do handoff
(`models/bomba.js`, `models/trocador.js`) já estavam vendorizados e o `viewer3d.js` já
despachava para eles; o que faltava era o lado Julia — `modelo_3d` devolvia `""`.

Conferido: **o 3D lê exatamente as grandezas que a elevação SVG cota**, do mesmo ponto do
cursor, e nenhum dos dois recalcula nada.

| método | a elevação desenha | o visor recebe |
|---|---|---|
| `MoranPumpSizing` | `svg_linha_bomba(d, dn, h)` | `dn` |
| `SaariLMTD` | `svg_trocador(d, l, passes)` | `n-tubos`, `l`, `passes` |

`modelo3d_de` é o envelope para quem **não** é vaso: a bomba e o trocador não têm
`geometry_from`, `PhaseLayer` nem β, então `atributos_3d` não os serviria.

A Análise Pinch continua sem 3D, e a razão mudou de "não conferido" para a verdadeira:
ela não dimensiona equipamento nenhum — não há o que mostrar em três dimensões.

Verificado com o servidor no ar: `/api/bomba-centrifuga/desenho` traz
`modelo3d = {bomba, dn 250.0}`, que é o DN que o cartão anuncia. **A aparência do 3D
continua sendo conferência no navegador do usuário**, pela mesma razão do §4: o
`--screenshot` do Firefox não compõe WebGL em software.

### 6.2 Os artboards por box — o enunciado estava torto

A lacuna prometia "replicar os artboards por box", e replicá-los ao pé da letra seria
**regressão**: os sete artboards são sete telas porque um mockup desenha cada caso, mas
no app é **uma** página genérica, e o que muda entre boxes já vem de `esquema`,
`result_fields`, `sweep_columns` e `figuras`. Sete páginas com campos escritos à mão
quebrariam a regra do Sprint 7 — a interface nunca cita um parâmetro pelo nome — que a
guarda de vocabulário do smoke existe para impor.

O que a lacuna de fato pedia é o **chrome compartilhado**, e a comparação mostrou que ele
já estava replicado desde este passo:

| medida | artboard | `app.css` |
|---|---|---|
| grade das colunas | `23.5% minmax(0,1fr) 23.5%` | idem (`--col-lado`) |
| `gap` do `main` | 12px | 12px |
| altura do cabeçalho | 42px | 40px |
| marca | 22px, largura automática | idem |
| coluna de casos | seletor de arquivo + Abrir/Salvar/Salvar como | idem |

A diferença é de 2 px numa altura de cabeçalho. Não se mexeu: o artboard é gabarito
visual, não medida de fabricação, e trocar 40 por 42 reflui a barra de status e os
gráficos para ganhar nada.

### 6.3 O menu — e o defeito que estava atrás dele

O menu saía em **coluna única**, com a tela inteira vazia à direita, quando a folha de
estilo pedia `repeat(auto-fill, minmax(min(250px, 100%), 1fr))`.

A causa não estava em nada que o menu declarasse. `align-items: start` vem do seletor
`main`, onde é o certo — lá as três colunas do dimensionamento não podem esticar até a
mais alta. Em `main.menu`, que é flex-**coluna**, a mesma declaração passa a significar
"encolha cada filho até o conteúdo": a grade media a largura de um cartão só, e
`auto-fill` concluía, corretamente, que cabia uma coluna.

`main.menu { align-items: stretch; }` — sete cartões em cinco colunas, como o artboard.

É a classe de defeito que teste de rota nenhum pega (o HTML sempre esteve correto) e que
só aparece com a tela aberta. A guarda nova é a **declaração explícita**: se ela sumir, a
herança volta a valer em silêncio.

### 6.4 Ícones: a gramática do Lucide, não o acervo

Adotado o que o DS de fato especifica: `stroke-width` **1.5** (estava 1.6), caixa 24×24,
pontas e junções redondas.

**Não** se trocaram os desenhos por ícones do Lucide, e não é preguiça: o Lucide não tem
separador trifásico, vaso knockout, tratador eletrostático nem curva composta de Pinch.
O que existiria seria uma engrenagem para a bomba e um cilindro para os cinco vasos —
sete cartões que o usuário não distingue de relance, que é exatamente o trabalho que o
ícone faz no menu. Trocar melhoraria a aderência ao acervo e pioraria a tela.

### 6.5 Verificação

```sh
julia --project=.   test/runtests.jl     # 5319 passam, 4 broken (pré-existentes)
julia --project=app app/smoke.jl         # 3634 passam
```

| guarda nova | o que impede |
|---|---|
| `main.menu` declara `align-items: stretch`, e `.grade-boxes` segue em `auto-fill` | o menu voltar a colapsar em coluna única |
| o 3D da bomba e do trocador recebe as grandezas do cursor, iguais às da elevação | o visor e o desenho mostrarem equipamentos diferentes |

Conferido no navegador: o menu monta em cinco colunas; a tela do separador monta com o
caso-ouro correto (6300 mm · 18,59 m · 24,78 m · SR 3,93).
