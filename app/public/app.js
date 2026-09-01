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
// `true` quando há edição que ainda não foi para o disco. Só serve para avisar antes
// de Abrir, que substitui a lista inteira — sem o aviso, um clique errado apaga um
// estudo inteiro sem nada a desfazer.
let sujo = false;
// Qual aplicação esta tela é — vem do servidor junto com o estado inicial, e prefixa
// toda chamada de API. A tela não sabe o que é um separador: ela sabe o id do box e os
// descritores que o servidor mandou.
let box = "";

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

function ocupado(sim) {
  // Abrir e salvar entram na lista: as duas escrevem (uma troca o estado inteiro, a
  // outra grava um arquivo) e um duplo clique enquanto a primeira está em voo mandaria
  // a segunda com o estado do meio do caminho.
  for (const id of ["btn-dimensionar", "btn-exportar",
                    "btn-abrir", "btn-salvar", "btn-salvar-como"]) {
    q(id).disabled = sim;
  }
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
}

function escreverGlobais() {
  for (const inp of q("form-ajustes").querySelectorAll("input.campo")) {
    inp.value = globais[inp.dataset.chave] ?? "";
    limparInvalido(inp);
  }
}

function recarregarSeletor(rotulos) {
  const s = q("sel-caso");
  s.replaceChildren(...rotulos.map((nome, i) => {
    const o = document.createElement("option");
    o.value = String(i + 1);
    o.textContent = nome;
    return o;
  }));
  s.value = String(Math.min(Math.max(sel, 1), rotulos.length));
}

/** Rótulos do seletor, com a marca de desativado — o mesmo prefixo que `nomes_menu`. */
const rotulosLocais = () => casos.map((c) => (c.enabled ? c.name : "○ " + c.name));

// ---------------------------------------------------------------- resultados

function aplicarCartao(c) {
  q("r-d").textContent = c.d;
  q("r-leff").textContent = c.leff;
  q("r-lss").textContent = c.lss;
  q("r-sr").textContent = c.sr;
  q("r-sr").classList.toggle("fora", !c.sr_ok);
  q("r-volume").textContent = c.volume;
  q("r-governa").textContent = c.governa;
  q("r-caso").textContent = c.caso;
  q("r-teto").textContent = c.teto;
}

function aplicarTabela(linhas) {
  q("corpo-varredura").replaceChildren(...linhas.map((l) => {
    const tr = document.createElement("tr");
    if (l.centro) tr.className = "centro";
    else if (l.sr_ok) tr.className = "na-banda";
    for (const k of ["d", "leff", "lss", "sr"]) {
      const td = document.createElement("td");
      td.textContent = l[k];
      tr.appendChild(td);
    }
    return tr;
  }));
}

function aplicarDesenho(d) {
  q("titulo-vaso").textContent = d.titulo;
  q("fig-vaso").innerHTML = d.vaso;
  q("fig-corte").innerHTML = d.corte;
  q("fig-leff").innerHTML = d.leff;
  q("fig-sr").innerHTML = d.sr;
  q("legenda-casos").innerHTML = d.legenda;
}

/** Põe o cursor na grade do último resultado, sem disparar o handler de `input`. */
function aplicarGrade(novaGrade, dSel) {
  grade = novaGrade || [];
  const sl = q("slider-d");
  if (!grade.length) { sl.disabled = true; return; }
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
  q("valor-d").textContent = `${Math.round(grade[melhor])} mm`;
}

/** Aplica uma resposta completa de /api/estado ou /api/dimensionar. */
function aplicarEstado(e) {
  casos = e.casos;
  sel = e.sel;
  globais = e.globais;
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

  let msg = e.status;
  if (e.avisos && e.avisos.length) {
    for (const a of e.avisos) marcarInvalido(a);
    msg = `${e.avisos.length} campo(s) recusado(s): ${e.avisos[0].msg}` +
          (e.avisos.length > 1 ? " …" : "");
  }
  status(msg, e.status_ok && !(e.avisos && e.avisos.length));
}

/** Marca a caixa que o servidor recusou, e diz por quê ao lado dela. */
function marcarInvalido(aviso) {
  const tabela = aviso.escopo === "globais" ? "form-ajustes" : "form-campos";
  if (aviso.escopo !== "globais" && aviso.escopo !== `caso:${sel}`) return;
  const inp = q(tabela).querySelector(
    `input[data-chave="${aviso.chave}"][data-extremo="${aviso.extremo}"]`);
  if (!inp) return;
  inp.classList.add("invalido");
  inp.setAttribute("aria-invalid", "true");
  const erro = q(idErro(aviso.chave, aviso.extremo));
  erro && (erro.textContent = aviso.msg);
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
  q("valor-d").textContent = `${Math.round(d)} mm`;
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
  if (r.avisos && r.avisos.length) for (const a of r.avisos) marcarInvalido(a);
  status(r.status, r.status_ok);
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
    }
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

// Uma exceção não tratada deixaria a tela parada em "Carregando…" sem dizer por quê —
// e o usuário-alvo não vai abrir o console do navegador. Melhor a queixa na barra.
window.addEventListener("error", (e) =>
  status(`Falha na interface: ${e.message}`, false));
window.addEventListener("unhandledrejection", (e) =>
  status(`Falha na interface: ${e.reason}`, false));

iniciar();
