/*
 * FPSO_Siz — a camada de tela.
 *
 * Três regras que explicam o resto do arquivo:
 *
 * 1. NENHUM CAMPO É ESCRITO À MÃO. O formulário nasce de /api/esquema, que vem dos
 *    `ParameterSpec` declarados no core. Se um parâmetro novo precisar de código aqui,
 *    o descritor dele está faltando lá — é a regra de src/interfaces.jl.
 *
 * 2. ESTE ARQUIVO NÃO CONVERTE NÚMERO. Os valores viajam como texto ("1.025,8") nos
 *    dois sentidos; quem lê é `Formato.parse_num` e quem escreve é `Formato.num`, do
 *    lado do Julia. A regra PT-BR existe uma vez só. A única exceção é o cursor de
 *    diâmetro, que é um <input type=range> — inteiro, sem separador, sem ambiguidade.
 *
 * 3. O CURSOR NÃO REDIMENSIONA NADA. A varredura já está calculada; mover o cursor só
 *    troca a seleção, e o servidor devolve o desenho e os números daquele diâmetro.
 *    Por isso o "mexeu → viu" é imediato mesmo com o cálculo do outro lado do HTTP.
 */

"use strict";

const q = (id) => document.getElementById(id);

let esquema = null;      // descritores vindos do core
let casos = [];          // [{name, enabled, lo:{chave:"215,8"}, hi:{...}}]
let sel = 1;             // 1-based, como no Julia
let globais = {};        // {chave: "3000,0"}
let grade = [];          // diâmetros disponíveis no cursor, em mm
let arquivos = [];       // conjuntos de casos no disco: [{nome, rotulo, casos, gravavel}]
let arquivoAtual = "";   // nome do que está aberto ("" = nunca salvo)
// `true` quando há edição que ainda não foi para o disco. Avisa antes de Abrir (que
// substitui a lista inteira), antes de voltar ao menu, e antes de fechar a aba — sem o
// aviso, um clique errado apaga um estudo inteiro sem nada a desfazer.
let sujo = false;
// Saída que a pessoa já confirmou (o botão Sair, ou o link do menu depois do "Continuar?").
// Suprime a pergunta do `beforeunload`: duas caixas de diálogo para um clique só é o tipo
// de aviso que se aprende a fechar sem ler, e aí ele deixa de proteger o que quer que seja.
let saindoDeProposito = false;
// Qual aplicação esta tela é — vem do servidor junto com o estado inicial, e prefixa
// toda chamada de API. A tela não sabe o que é um separador: ela sabe o id do box e os
// descritores que o servidor mandou.
let box = "";
// Unidade do eixo varrido ("mm" num vaso), para o rótulo do cursor. Vem do esquema:
// era `mm` escrito à mão em dois lugares, o que fazia a tela conhecer a grandeza.
let unidadeEixo = "";
// Os campos que o servidor recusou na última resposta, de TODOS os casos.
//
// Precisa existir porque o servidor valida o conjunto inteiro (ver `aplicar!` em
// app/src/api.jl) e a tela mostra um caso por vez. Antes esta lista não era guardada: os
// avisos de outro caso eram descartados na hora, e os do caso à vista eram apagados por
// `escreverCaso` na primeira troca de caso e nunca repostos. O resultado era a barra
// dizendo "3 campo(s) recusado(s)" com nada marcado em lugar nenhum — a tela e o servidor
// deixando de se corresponder sem que nada denunciasse.
let avisosPendentes = [];

// ---------------------------------------------------------------- utilidades

function status(texto, ok = true) {
  const el = q("status");
  el.textContent = texto;
  el.classList.toggle("ruim", !ok);
}

/** fetch com erro de rede virando mensagem na barra, nunca exceção solta. */
async function pedir(url, opcoes) {
  try {
    const r = await fetch(url, opcoes);
    // O `Content-Type` é conferido ANTES de parsear. Sem esta guarda, uma resposta que
    // não fosse JSON (uma página de erro do Genie, por exemplo) fazia `r.json()` lançar,
    // e o `catch` lá embaixo escrevia "Sem conexão com o servidor" — mensagem falsa, e
    // que manda a pessoa procurar no lugar errado: o servidor respondeu, e respondeu
    // outra coisa. A falha de rede e a resposta inesperada não são o mesmo diagnóstico.
    const tipo = r.headers.get("content-type") || "";
    if (!tipo.includes("json")) {
      status(`O servidor respondeu algo inesperado (HTTP ${r.status}) em ${url}.`, false);
      return null;
    }
    const corpo = await r.json();
    if (!r.ok) {
      status(corpo.status || `Erro ${r.status} em ${url}`, false);
      return null;
    }
    return corpo;
  } catch (err) {
    // Abortar é o desfecho ESPERADO de uma requisição que ficou obsoleta (ver
    // `moverCursor`), não uma falha: quem abortou já disparou a substituta. Sem esta
    // guarda, arrastar o cursor escreveria "sem conexão" com o servidor no ar.
    if (err && err.name === "AbortError") return null;
    // Este, sim, acontece de verdade: o usuário fechou o programa com a aba aberta.
    status("Sem conexão com o servidor do FPSO_Siz. Ele ainda está aberto?", false);
    return null;
  }
}

const casoAtual = () => casos[Math.min(Math.max(sel, 1), casos.length) - 1];

// Tudo o que dispara requisição OU mexe em `casos`. Abrir e salvar entram porque as duas
// escrevem (uma troca o estado inteiro, a outra grava um arquivo) e um duplo clique
// enquanto a primeira está em voo mandaria a segunda com o estado do meio do caminho.
//
// Os seis últimos entraram depois: eles não disparam nada, mas EDITAM o estado local, e
// o `aplicarEstado` da resposta em voo sobrescreve `casos` inteiro. Criar um caso durante
// um "Abrir" o fazia desaparecer sem aviso quando a resposta chegava — o mesmo desfecho
// do duplo clique, por outro caminho.
const CONTROLES = ["btn-dimensionar", "btn-exportar",
                   "btn-abrir", "btn-salvar", "btn-salvar-como",
                   "btn-novo", "btn-duplicar", "btn-remover",
                   "sel-arquivo", "sel-caso", "slider-d"];

function ocupado(sim) {
  for (const id of CONTROLES) q(id).disabled = sim;
  // O cursor tem um dono: `aplicarGrade`, que o desabilita quando não há grade. Liberar
  // aqui sem consultá-la reabriria um cursor sobre nada depois de um Exportar num estado
  // inviável — e um cursor de um item só é um controle que mente sobre ter alternativas.
  if (!sim) q("slider-d").disabled = !grade.length;
  // `aria-busy` na barra de status: enquanto a operação corre, o leitor de tela sabe que
  // a mensagem ("Dimensionando…") é de trabalho em curso, e não o resultado final.
  q("status").setAttribute("aria-busy", sim ? "true" : "false");
}

// ---------------------------------------------------------------- formulário

/** id do <span> que carrega a queixa do servidor sobre uma caixa. */
const idErro = (chave, extremo) => `erro-${chave}-${extremo}`;

/**
 * Devolve a caixa ao estado válido.
 *
 * `aria-invalid` é REMOVIDO, nunca escrito como "false": um leitor de tela anuncia
 * "inválido: falso" em cada campo que carregue o atributo negado, e o formulário tem
 * cerca de cinquenta caixas.
 */
function limparInvalido(inp) {
  inp.classList.remove("invalido");
  inp.removeAttribute("aria-invalid");
  const erro = q(idErro(inp.dataset.chave, inp.dataset.extremo));
  erro && (erro.textContent = "");
}

/** Uma linha rótulo / mín / máx / unidade. `extremos` distingue campo de ajuste. */
function linhaCampo(spec, extremos) {
  const tr = document.createElement("tr");

  const td = document.createElement("td");
  td.className = "rotulo";
  td.textContent = spec.label;
  spec.note && (td.title = spec.note);
  tr.appendChild(td);

  for (const extremo of extremos) {
    const cel = document.createElement("td");
    const inp = document.createElement("input");
    inp.type = "text";
    inp.className = "campo";
    inp.inputMode = "decimal";
    inp.autocomplete = "off";
    inp.dataset.chave = spec.key;
    inp.dataset.extremo = extremo;
    // O rótulo é uma <td>, e não um <label for>, porque são DUAS caixas por rótulo:
    // associar as duas ao mesmo texto faria o leitor de tela anunciar "vazão de óleo"
    // nas duas, sem distinguir o mínimo do máximo. Daí o nome acessível em cada caixa.
    // Sem ele, cada uma das ~50 caixas é anunciada como "caixa de edição, em branco".
    inp.setAttribute("aria-label", extremos.length === 1
      ? `${spec.label} (${spec.unit})`
      : `${spec.label}, ${extremo === "lo" ? "mínimo" : "máximo"} (${spec.unit})`);
    inp.title = `${spec.label} — de ${spec.min} a ${spec.max} ${spec.unit}` +
                (spec.note ? `\n${spec.note}` : "");

    // A queixa do servidor vive ao lado da caixa que ela recusa, não só na barra de
    // status: a classe `.invalido` é cor, e cor sozinha não informa quem não a
    // distingue. O <span> fica vazio (e sem ocupar espaço) enquanto não há queixa.
    const erro = document.createElement("span");
    erro.className = "erro-campo";
    erro.id = idErro(spec.key, extremo);
    inp.setAttribute("aria-describedby", erro.id);

    inp.addEventListener("input", () => {
      limparInvalido(inp);
      esquecerAviso(spec.key, extremo, extremos.length === 1);
      if (extremos.length === 1) {
        // Os ajustes de grade NÃO vão para o arquivo de casos (ver `salvar_casos!` em
        // app/src/state.jl), então mexer neles não deixa nada por salvar.
        globais[spec.key] = inp.value;
      } else {
        casoAtual()[extremo][spec.key] = inp.value;
        sujo = true;
      }
    });
    // Enter em qualquer caixa dimensiona: é o gesto que o engenheiro espera.
    inp.addEventListener("keydown", (e) => { if (e.key === "Enter") dimensionar(); });
    cel.appendChild(inp);
    cel.appendChild(erro);
    tr.appendChild(cel);
  }

  const un = document.createElement("td");
  un.className = "unidade";
  un.textContent = spec.unit;
  tr.appendChild(un);
  return tr;
}

function montarFormulario() {
  const campos = q("form-campos").querySelector("tbody");
  campos.replaceChildren(...esquema.campos.map((s) => linhaCampo(s, ["lo", "hi"])));

  const ajustes = q("form-ajustes").querySelector("tbody");
  ajustes.replaceChildren(...esquema.ajustes.map((s) => linhaCampo(s, ["lo"])));

  q("rotulo-equipamento").textContent = esquema.equipamento;
  q("rotulo-metodo").textContent = esquema.metodo;

  const eixo = esquema.eixo || { label: "", unit: "" };
  unidadeEixo = eixo.unit;
  q("rotulo-cursor").textContent = eixo.label;
}

/** Reescreve as caixas com o caso selecionado. */
function escreverCaso() {
  const c = casoAtual();
  if (!c) return;
  q("nome-caso").value = c.name;
  q("chk-ativo").checked = c.enabled;
  for (const inp of q("form-campos").querySelectorAll("input.campo")) {
    inp.value = c[inp.dataset.extremo][inp.dataset.chave] ?? "";
    limparInvalido(inp);
  }
  // Repõe as marcas do caso que passou a estar à vista. É o passo que faltava: sem ele,
  // trocar de caso e voltar apagava a queixa do servidor de vez.
  aplicarAvisos();
}

function escreverGlobais() {
  for (const inp of q("form-ajustes").querySelectorAll("input.campo")) {
    inp.value = globais[inp.dataset.chave] ?? "";
    limparInvalido(inp);
  }
  aplicarAvisos();
}

function recarregarSeletor(rotulos) {
  const s = q("sel-caso");
  const comAviso = casosComAviso();
  s.replaceChildren(...rotulos.map((nome, i) => {
    const o = document.createElement("option");
    o.value = String(i + 1);
    // A marca no SELETOR é o que torna visível um campo recusado num caso que não está à
    // vista: sem ela, a única pista de que o caso 3 tem um valor ilegível é uma frase na
    // barra de status, e ninguém sabe onde procurar. Mesmo idioma do "○ " de desativado
    // e do "◀ governa" do memorial — símbolo mais texto, nunca cor sozinha.
    o.textContent = (comAviso.has(i + 1) ? "⚠ " : "") + nome;
    return o;
  }));
  s.value = String(Math.min(Math.max(sel, 1), rotulos.length));
}

/** Rótulos do seletor, com a marca de desativado — o mesmo prefixo que `nomes_menu`. */
const rotulosLocais = () => casos.map((c) => (c.enabled ? c.name : "○ " + c.name));

// ---------------------------------------------------------------- resultados

/*
 * O cartão, a tabela e as figuras nascem do JSON — nada aqui sabe que existe um
 * diâmetro, um Leff ou uma esbeltez.
 *
 * Até o Sprint 6 esta seção escrevia em oito `id` fixos (`r-d`, `r-leff`, `r-sr`…),
 * lia quatro colunas pelo nome e enchia quatro `<div>` de figura. Isso fixava a tela no
 * separador: uma bomba não tem esbeltez para pôr no `r-sr`, e a linha ficaria vazia sem
 * que nada denunciasse. Agora o servidor manda rótulo e valor, e a tela desenha o que
 * vier — a mesma regra que o formulário já seguia desde o Sprint 0.
 */

function aplicarCartao(campos) {
  const filhos = [];
  for (const c of campos) {
    const dt = document.createElement("dt");
    dt.textContent = c.rotulo;
    const dd = document.createElement("dd");
    dd.textContent = c.valor;
    if (c.destaque) dd.className = "destaque grande";
    if (c.status === "erro") dd.classList.add("fora");
    filhos.push(dt, dd);
  }
  q("cartao").replaceChildren(...filhos);
}

function aplicarTabela(t) {
  q("cabecalho-varredura").replaceChildren(...t.colunas.map((rotulo) => {
    const th = document.createElement("th");
    th.textContent = rotulo;
    return th;
  }));
  q("corpo-varredura").replaceChildren(...t.linhas.map((l) => {
    const tr = document.createElement("tr");
    if (l.centro) tr.className = "centro";
    else if (l.ok) tr.className = "na-banda";
    for (const v of l.valores) {
      const td = document.createElement("td");
      td.textContent = v;
      tr.appendChild(td);
    }
    return tr;
  }));
}

/*
 * As três áreas de figura que o HTML oferece.
 *
 * Escritas por extenso, e não montadas com `"area-" + f.area`: o teste que cruza os id
 * do HTML com os do JS procura chamadas de `q` com string literal, e um id construído
 * por concatenação passaria despercebido por ele — que é justamente o teste que existe
 * para pegar um id renomeado num arquivo e esquecido no outro.
 */
const AREAS = {
  principal:  () => q("area-principal"),
  secundaria: () => q("area-secundaria"),
  grafico:    () => q("area-grafico"),
};

/** As figuras vão para a área que cada uma declara; áreas sem figura ficam vazias. */
function aplicarDesenho(d) {
  const conteudo = { principal: [], secundaria: [], grafico: [] };
  let legenda = "";
  // O título é acumulado e escrito UMA vez, no fim. Antes ele só era escrito quando havia
  // figura principal com título — e o fallback genérico de `figuras` não declara nenhuma.
  // O resultado era o título do estado anterior de pé sobre uma área que ficara vazia: a
  // tela dizendo "Elevação — d = 6300 mm" sobre um espaço em branco.
  let tituloPrincipal = "";
  for (const f of d.figuras) {
    if (!conteudo[f.area]) continue;       // área desconhecida: ignora, não quebra
    const div = document.createElement("div");
    div.className = "figura";
    div.innerHTML = f.svg;
    conteudo[f.area].push(div);
    // Só a figura principal tem título visível: as outras trazem o seu dentro do SVG.
    if (f.area === "principal" && f.titulo) tituloPrincipal = f.titulo;
    if (f.legenda) legenda = f.legenda;
  }
  q("titulo-figura").textContent = tituloPrincipal;
  q("legenda-figura").innerHTML = legenda;
  for (const [nome, filhos] of Object.entries(conteudo)) {
    AREAS[nome]().replaceChildren(...filhos);
  }
  q("legenda-casos").innerHTML = d.legenda;
}

/** Põe o cursor na grade do último resultado, sem disparar o handler de `input`. */
function aplicarGrade(novaGrade, dSel) {
  grade = novaGrade || [];
  const sl = q("slider-d");
  if (!grade.length) {
    // Estado inviável: sem grade não há valor, e o que estava escrito era do resultado
    // anterior. Some da tela e some do leitor de tela pelo mesmo gesto.
    sl.disabled = true;
    sl.removeAttribute("aria-valuetext");
    q("valor-d").textContent = "—";
    return;
  }
  sl.disabled = false;
  sl.min = 0;
  sl.max = grade.length - 1;
  // Índice em vez do valor: a grade não é obrigada a ter passo constante, e o
  // <input type=range> só sabe andar em passos iguais.
  let melhor = 0;
  for (let i = 1; i < grade.length; i++) {
    if (Math.abs(grade[i] - dSel) < Math.abs(grade[melhor] - dSel)) melhor = i;
  }
  sl.value = melhor;
  escreverValorEixo(grade[melhor]);
}

/**
 * O valor do cursor, na tela e para o leitor de tela.
 *
 * `aria-valuetext` é obrigatório aqui, e não enfeite: o `value` do `<input type=range>` é
 * o ÍNDICE na grade (ver a nota em `aplicarGrade` — a grade não tem passo constante), e é
 * o `value` que o leitor de tela anuncia. Sem o texto, arrastar o cursor lia "3 de 12" em
 * vez de "5550 mm": o número que a pessoa precisa ouvir é o único que ela não ouvia.
 */
function escreverValorEixo(v) {
  const texto = `${Math.round(v)} ${unidadeEixo}`;
  q("valor-d").textContent = texto;
  q("slider-d").setAttribute("aria-valuetext", texto);
}

/** Aplica uma resposta completa de /api/estado ou /api/dimensionar. */
function aplicarEstado(e) {
  casos = e.casos;
  sel = e.sel;
  globais = e.globais;
  // Antes de qualquer escrita na tela: `recarregarSeletor` marca os casos com aviso e
  // `escreverCaso` repõe as caixas recusadas, e os dois leem esta lista. Os avisos
  // pertencem à resposta que os produziu — a nova apaga os da anterior, como já vale
  // para o `memorial`.
  avisosPendentes = e.avisos || [];
  if (e.arquivo !== undefined) arquivoAtual = e.arquivo;
  if (e.lista) aplicarLista(e.lista);
  recarregarSeletor(e.rotulos);
  escreverCaso();
  escreverGlobais();
  aplicarGrade(e.grade, e.d_sel);
  aplicarCartao(e.cartao);
  aplicarTabela(e.tabela);
  e.desenho && aplicarDesenho(e.desenho);
  esquecerMemorial();

  status(avisosPendentes.length ? textoDosAvisos() : e.status,
         e.status_ok && !avisosPendentes.length);
}

// ------------------------------------------------- avisos de validação
//
// O servidor valida TODOS os casos e devolve um aviso por caixa recusada, com o escopo
// ("caso:3" ou "globais") que endereça a caixa na tela. A tela mostra um caso por vez,
// então três coisas precisam acontecer, e só a primeira acontecia:
//
//   1. marcar a caixa recusada do caso à vista;
//   2. repor essa marca quando se volta ao caso, depois de passar por outro;
//   3. dizer que existe caixa recusada num caso que NÃO está à vista — senão a barra
//      anuncia "3 campo(s) recusado(s)" e não há nada marcado em lugar nenhum.

/** Índice 1-based do caso a que o aviso se refere, ou `null` se for de ajuste global. */
function casoDoAviso(aviso) {
  const m = /^caso:(\d+)$/.exec(aviso.escopo || "");
  return m ? Number(m[1]) : null;
}

/** Os índices de caso que têm alguma caixa recusada. */
function casosComAviso() {
  const s = new Set();
  for (const a of avisosPendentes) {
    const i = casoDoAviso(a);
    i !== null && s.add(i);
  }
  return s;
}

/** Marca, no formulário à vista, todas as caixas recusadas que lhe pertencem. */
function aplicarAvisos() {
  for (const aviso of avisosPendentes) {
    const i = casoDoAviso(aviso);
    if (i !== null && i !== sel) continue;    // é de outro caso: o seletor o denuncia
    const tabela = i === null ? "form-ajustes" : "form-campos";
    const inp = q(tabela).querySelector(
      `input[data-chave="${aviso.chave}"][data-extremo="${aviso.extremo}"]`);
    if (!inp) continue;
    inp.classList.add("invalido");
    inp.setAttribute("aria-invalid", "true");
    const erro = q(idErro(aviso.chave, aviso.extremo));
    erro && (erro.textContent = aviso.msg);
  }
}

/**
 * A frase da barra de status.
 *
 * Nomeia o CASO: a mensagem era `avisos[0].msg` crua, e o primeiro aviso costuma ser de
 * um caso que não está à vista — a pessoa lia "Vazão de óleo: valor ilegível" olhando
 * para uma vazão de óleo perfeitamente legível.
 */
function textoDosAvisos() {
  const a = avisosPendentes[0];
  const i = casoDoAviso(a);
  const onde = i === null ? "Ajustes"
             : (casos[i - 1] ? `Caso '${casos[i - 1].name}'` : `Caso ${i}`);
  return `${avisosPendentes.length} campo(s) recusado(s). ${onde} — ${a.msg}` +
         (avisosPendentes.length > 1 ? " …" : "");
}

/**
 * Descarta TODOS os avisos.
 *
 * Chamado ao criar e ao remover caso. O escopo do aviso é POSICIONAL (`"caso:3"`) — é
 * como ele endereça a caixa na tela —, então mexer na lista de casos o desendereça: um
 * aviso do caso 3 passaria a marcar o que era o caso 4. É a mesma armadilha da herança
 * por posição do Sprint 3, e a saída aqui é mais simples do que lá: os avisos pertencem
 * à última resposta do servidor, e a lista que ela validou deixou de existir.
 */
function esquecerAvisos() {
  avisosPendentes = [];
  for (const inp of q("form-campos").querySelectorAll("input.campo")) limparInvalido(inp);
}

/**
 * Esquece o aviso da caixa que o usuário acabou de editar.
 *
 * `limparInvalido` já tira a marca da caixa; sem isto, o `⚠` do seletor ficaria de pé
 * sobre um caso que a pessoa acabou de corrigir — pior que não ter marca nenhuma, porque
 * uma marca que não some deixa de ser lida.
 */
function esquecerAviso(chave, extremo, global) {
  const antes = avisosPendentes.length;
  avisosPendentes = avisosPendentes.filter((a) => {
    const i = casoDoAviso(a);
    const minha = global ? i === null : i === sel;
    return !(minha && a.chave === chave && a.extremo === extremo);
  });
  antes !== avisosPendentes.length && recarregarSeletor(rotulosLocais());
}

// ---------------------------------------------------------------- ações

const corpoAtual = () => JSON.stringify({ casos, globais, sel });

async function dimensionar() {
  ocupado(true);
  status("Dimensionando…");
  const r = await pedir(`/api/${box}/dimensionar`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: corpoAtual(),
  });
  ocupado(false);
  r && aplicarEstado(r);
}

async function exportar() {
  ocupado(true);
  const r = await pedir(`/api/${box}/exportar`, { method: "POST" });
  ocupado(false);
  r && status(r.status, r.status_ok);
}

async function sair() {
  if (!confirm("Encerrar o FPSO_Siz?\n\nO que já foi exportado continua salvo.")) return;
  saindoDeProposito = true;
  ocupado(true);
  status("Encerrando…");
  // A resposta chega antes de o servidor descer (ver a rota /api/parar); o `catch`
  // cobre o caso de ele descer antes mesmo disso.
  try {
    await fetch("/api/parar", { method: "POST" });
  } catch (_) { /* já caiu — é o desfecho esperado */ }
  document.body.innerHTML =
    '<p style="padding:24px;font:14px system-ui">FPSO_Siz encerrado. ' +
    "Pode fechar esta aba.</p>";
}

// O cursor troca só a seleção, então a resposta é barata; ainda assim, arrastar
// dispara dezenas de eventos por segundo. O atraso curto corta a enxurrada sem que o
// movimento pareça travado.
//
// O debounce sozinho NÃO basta, e é a diferença entre o que ele faz e o que parece
// fazer: ele espaça os disparos, mas nada garante a ordem de CHEGADA. Num arrasto lento
// ele dispara várias vezes, e uma resposta antiga que chegue depois de uma nova repinta
// o desenho e o cartão num diâmetro que o cursor já deixou para trás. Por isso o
// `AbortController`: antes de disparar, cancela-se a requisição anterior, e só a última
// pode chegar ao DOM.
let pendente = null;
let emVoo = null;
function moverCursor() {
  const i = Number(q("slider-d").value);
  if (!grade.length) return;
  const d = grade[i];
  escreverValorEixo(d);
  clearTimeout(pendente);
  pendente = setTimeout(async () => {
    if (emVoo) emVoo.abort();
    const meu = (emVoo = new AbortController());
    const r = await pedir(`/api/${box}/desenho`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ d: String(d) }),
      signal: meu.signal,
    });
    if (!r) return;
    aplicarDesenho(r.desenho);
    aplicarCartao(r.cartao);
    aplicarTabela(r.tabela);
  }, 30);
}

// ---------------------------------------------------------------- memorial

// `null` = ainda não pedido, ou obsoleto. O rastro pertence ao resultado que o
// produziu: assim que o usuário redimensiona, o que está na tela deixa de valer.
let memorial = null;

/** Descarta o rastro. Se o painel estiver aberto, repõe na hora; senão, ao abrir. */
function esquecerMemorial() {
  memorial = null;
  if (q("memorial").open) carregarMemorial();
}

async function carregarMemorial() {
  const r = await pedir(`/api/${box}/memorial`);
  if (!r) return;
  memorial = r;

  const s = q("sel-memorial");
  const guardado = s.value;
  s.replaceChildren(...memorial.casos.map((c, i) => {
    const o = document.createElement("option");
    o.value = String(i);
    // A mesma marca da legenda dos gráficos, pelo mesmo motivo: de dez casos de canto,
    // o que interessa conferir primeiro é o que governou o projeto.
    o.textContent = c.nome === memorial.governante ? `${c.nome}  ◀ governa` : c.nome;
    return o;
  }));
  // Preserva o caso que estava sendo lido, quando ele sobrevive ao novo cálculo.
  s.value = guardado && Number(guardado) < memorial.casos.length ? guardado : "0";
  escreverMemorial();
}

function escreverMemorial() {
  const alvo = q("corpo-memorial");
  const caso = memorial && memorial.casos[Number(q("sel-memorial").value)];
  if (!caso) {
    const p = document.createElement("p");
    p.className = "dica";
    p.textContent = "Sem rastro de cálculo — dimensione primeiro.";
    alvo.replaceChildren(p);
    return;
  }

  const partes = [];
  for (const b of caso.blocos) {
    const h = document.createElement("h3");
    h.textContent = b.titulo;
    const pre = document.createElement("pre");
    // `textContent`, nunca `innerHTML`: nome de caso e fórmula vêm do TOML do usuário
    // e do expansor de cantos, e aqui não passam por `escapa` — é o DOM que garante.
    pre.textContent = b.linhas.join("\n");
    partes.push(h, pre);
  }
  const fecho = document.createElement("pre");
  fecho.className = "fecho";
  fecho.textContent = caso.fecho;
  partes.push(fecho);
  alvo.replaceChildren(...partes);
}

// ---------------------------------------------------------------- arquivos

/** Preenche o seletor de arquivo com a lista que o servidor mandou. */
function aplicarLista(lista) {
  arquivos = lista.arquivos || [];
  arquivoAtual = lista.atual || arquivoAtual;

  const s = q("sel-arquivo");
  s.replaceChildren(...arquivos.map((a) => {
    const o = document.createElement("option");
    o.value = a.nome;
    // O rótulo declarado no TOML é o que identifica o estudo; o nome do arquivo vem
    // junto porque é por ele que a pessoa o encontra na pasta. O cadeado marca o que
    // veio de fábrica: salvar por cima faz uma cópia na pasta do usuário, não edita o
    // exemplo — e é melhor a pessoa saber disso antes de clicar do que depois.
    o.textContent = `${a.gravavel ? "" : "🔒 "}${a.rotulo} — ${a.nome} (${a.casos})`;
    return o;
  }));
  if (arquivoAtual) s.value = arquivoAtual;
  q("btn-salvar").textContent = arquivoAtual ? "Salvar" : "Salvar…";
}

async function recarregarLista() {
  const r = await pedir(`/api/${box}/casos/arquivos`);
  r && aplicarLista(r);
}

/** O registro da lista com este nome, ou `undefined`. */
const acharArquivo = (nome) => arquivos.find((a) => a.nome === nome);

async function abrirArquivo() {
  const nome = q("sel-arquivo").value;
  if (!nome) return;
  if (nome === arquivoAtual && !sujo) {
    status(`'${nome}' já está aberto.`);
    return;
  }
  // Abrir SUBSTITUI a lista de casos inteira. Sem esta pergunta, um clique no lugar
  // errado descarta o estudo em edição e não há como desfazer.
  if (sujo && !confirm(
        "Há alterações que ainda não foram salvas.\n\n" +
        `Abrir '${nome}' descarta essas alterações. Continuar?`)) return;

  ocupado(true);
  status(`Abrindo '${nome}'…`);
  const r = await pedir(`/api/${box}/casos/abrir`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ arquivo: nome }),
  });
  ocupado(false);
  if (!r) return;
  aplicarEstado(r);
  // `aplicarEstado` só limpa a marca depois de um estado que veio do disco — é aqui,
  // e não em `dimensionar`, que o que está na tela passa a existir num arquivo.
  sujo = false;
}

/**
 * Grava os casos da tela.
 *
 * `comoNovo` força a pergunta do nome. Sem arquivo aberto ela é feita de qualquer
 * jeito: "Salvar" sobre nada não tem onde gravar.
 */
async function salvarArquivo(comoNovo) {
  let nome = arquivoAtual;
  let rotulo = "";

  if (comoNovo || !nome) {
    const sugestao = nome || "meus_casos.toml";
    const dado = prompt("Nome do arquivo de casos:", sugestao);
    if (dado === null) return;
    nome = dado.trim();
    if (!nome) return;
    if (!nome.toLowerCase().endsWith(".toml")) nome += ".toml";
    // Rótulo novo a partir do nome: é o que o seletor mostra, e um arquivo sem rótulo
    // apareceria ali só pelo nome de arquivo.
    rotulo = nome.slice(0, -5).replace(/[_-]+/g, " ");
    const existente = acharArquivo(nome);
    if (existente && !confirm(`'${nome}' já existe. Substituir?`)) return;
  } else {
    const atual = acharArquivo(nome);
    rotulo = atual ? atual.rotulo : "";
    // Exemplo de fábrica: o arquivo original não é tocado — a cópia vai para a pasta
    // gravável do usuário e passa a ter precedência sobre ele. Ver `dirs_casos()`.
    if (atual && !atual.gravavel &&
        !confirm(`'${nome}' é um exemplo que acompanha o programa.\n\n` +
                 "Salvar cria uma cópia sua, que passa a ser usada no lugar dele. " +
                 "Continuar?")) return;
  }

  ocupado(true);
  status(`Salvando '${nome}'…`);
  const r = await pedir(`/api/${box}/casos/salvar`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    // Vai o conteúdo da tela junto: o servidor grava o que está à vista, e não o que
    // ele tinha da última vez que se clicou em Dimensionar.
    body: JSON.stringify({ casos, globais, sel, arquivo: nome, rotulo }),
  });
  ocupado(false);
  if (!r) return;

  r.lista && aplicarLista(r.lista);
  // Mesmo tratamento do `aplicarEstado`: um campo recusado ao salvar precisa aparecer no
  // seletor quando é de outro caso, e sobreviver a uma troca de caso.
  avisosPendentes = r.avisos || [];
  if (avisosPendentes.length) {
    recarregarSeletor(rotulosLocais());
    aplicarAvisos();
  }
  status(avisosPendentes.length ? textoDosAvisos() : r.status, r.status_ok);
  if (r.ok) sujo = false;
}

// ---------------------------------------------------------------- casos

function trocarCaso(novo) {
  sel = novo;
  escreverCaso();
}

// Caso nasce SEM `id`: o servidor atribui um ao recebê-lo. É assim que ele distingue
// "caso novo" de "caso que eu já conhecia" e sabe de qual herdar o valor de um campo
// recusado — ver `novo_id` em app/src/state.jl. Daí o `delete` ao duplicar: sem ele a
// cópia carregaria a identidade do original e as duas seriam o mesmo caso para o
// servidor.
function novoCaso(copia) {
  const base = copia
    ? { ...casoAtual(), name: casoAtual().name + " (cópia)",
        lo: { ...casoAtual().lo }, hi: { ...casoAtual().hi } }
    : { name: `Caso ${casos.length + 1}`, enabled: true,
        lo: Object.fromEntries(esquema.campos.map((s) => [s.key, s.default])),
        hi: Object.fromEntries(esquema.campos.map((s) => [s.key, s.default])) };
  delete base.id;
  casos.push(base);
  sujo = true;
  sel = casos.length;
  esquecerAvisos();
  recarregarSeletor(rotulosLocais());
  escreverCaso();
}

function removerCaso() {
  if (casos.length <= 1) {
    status("O último caso não pode ser removido — o envelope precisa de ao menos um.", false);
    return;
  }
  casos.splice(sel - 1, 1);
  sujo = true;
  sel = Math.min(sel, casos.length);
  esquecerAvisos();
  recarregarSeletor(rotulosLocais());
  escreverCaso();
}

// ---------------------------------------------------------------- início

async function iniciar() {
  // O servidor embute esquema e estado no próprio HTML (ver `pagina_inicial` em
  // src/server.jl): a primeira pintura já vem completa, sem piscar. Os `fetch` ficam
  // de reserva para quando a página for aberta por outro caminho.
  const semente = window.__INICIAL__ || {};
  box = semente.box || "";
  esquema = semente.esquema || (await pedir(`/api/${box}/esquema`));
  if (!esquema) return;
  montarFormulario();

  q("sel-caso").addEventListener("change", (e) => trocarCaso(Number(e.target.value)));
  // Voltar não perde o trabalho — o estado de cada box fica no servidor — mas perde o
  // que foi digitado e ainda não foi enviado, porque a tela só manda ao dimensionar ou
  // ao salvar. Daí o aviso.
  q("link-menu").addEventListener("click", (e) => {
    if (sujo && !confirm("Há alterações que ainda não foram enviadas ao servidor.\n\n" +
                         "Voltar ao menu descarta essas alterações. Continuar?")) {
      e.preventDefault();
      return;
    }
    // Já perguntou: o `beforeunload` não pergunta de novo. Duas caixas de diálogo para
    // um clique só é o tipo de aviso que a pessoa aprende a fechar sem ler.
    saindoDeProposito = true;
  });
  q("btn-abrir").addEventListener("click", abrirArquivo);
  q("btn-salvar").addEventListener("click", () => salvarArquivo(false));
  q("btn-salvar-como").addEventListener("click", () => salvarArquivo(true));
  q("btn-novo").addEventListener("click", () => novoCaso(false));
  q("btn-duplicar").addEventListener("click", () => novoCaso(true));
  q("btn-remover").addEventListener("click", removerCaso);
  q("btn-dimensionar").addEventListener("click", dimensionar);
  q("btn-exportar").addEventListener("click", exportar);
  q("btn-sair").addEventListener("click", sair);
  q("slider-d").addEventListener("input", moverCursor);

  // Carrega ao abrir pela primeira vez, e de novo se o rastro tiver sido invalidado
  // por um novo dimensionamento enquanto o painel estava fechado.
  q("memorial").addEventListener("toggle", () => {
    if (q("memorial").open && !memorial) carregarMemorial();
  });
  q("sel-memorial").addEventListener("change", escreverMemorial);

  q("nome-caso").addEventListener("input", (e) => {
    casoAtual().name = e.target.value;
    sujo = true;
    const s = q("sel-caso");
    const guardado = s.value;
    recarregarSeletor(rotulosLocais());
    s.value = guardado;
  });
  q("chk-ativo").addEventListener("change", (e) => {
    casoAtual().enabled = e.target.checked;
    sujo = true;
    const guardado = q("sel-caso").value;
    recarregarSeletor(rotulosLocais());
    q("sel-caso").value = guardado;
  });

  const inicial = semente.estado || (await pedir(`/api/${box}/estado`));
  inicial && aplicarEstado(inicial);

  // A lista de arquivos NÃO viaja no estado embutido: ela lê o diretório a cada pedido,
  // e o estado inicial é montado uma vez só. Pedi-la depois da primeira pintura também
  // evita segurar o desenho da tela por causa de um `readdir`.
  await recarregarLista();
  sujo = false;
}

// Fechar ou recarregar a aba com edição pendente descartava o estudo em silêncio. Abrir
// e Voltar ao menu já perguntavam desde o Sprint 3; fechar a aba, que é o gesto mais
// fácil de fazer sem querer, não perguntava nada — e o estado da tela só existe no
// servidor depois de Dimensionar, ou no disco depois de Salvar.
//
// O navegador mostra um texto próprio, não o nosso: `preventDefault` é o que pede a
// pergunta, e `returnValue` fica pela compatibilidade com o que ainda não segue a
// especificação atual.
window.addEventListener("beforeunload", (e) => {
  if (!sujo || saindoDeProposito) return;
  e.preventDefault();
  e.returnValue = "";
});

// Uma exceção não tratada deixaria a tela parada em "Carregando…" sem dizer por quê —
// e o usuário-alvo não vai abrir o console do navegador. Melhor a queixa na barra.
window.addEventListener("error", (e) =>
  status(`Falha na interface: ${e.message}`, false));
window.addEventListener("unhandledrejection", (e) =>
  status(`Falha na interface: ${e.reason}`, false));

iniciar();
