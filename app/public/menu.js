/*
 * FPSO_Siz — o menu de abertura.
 *
 * A grade de cartões nasce de `config/catalogo.toml`, que o servidor injeta em
 * `window.__INICIAL__`. Nenhum equipamento é citado neste arquivo: acrescentar uma
 * aplicação é editar o TOML, e é o teste em `test/architecture.jl` que garante que um
 * box marcado `ativo` de fato resolve no registro do core.
 *
 * Os ícones são SVG escrito à mão em `icones.js`. Nada de CDN nem de fonte de ícones:
 * o programa roda offline, e o executável do PackageCompiler não pode depender de rede.
 */

"use strict";

const q = (id) => document.getElementById(id);

function status(texto, ok = true) {
  const el = q("status");
  el.textContent = texto;
  el.classList.toggle("ruim", !ok);
}

/** Um cartão. Ativo vira `<a>` navegável; pendente vira `<div>` que diz por quê. */
function cartao(box) {
  const el = document.createElement(box.ativo ? "a" : "div");
  el.className = "box" + (box.ativo ? "" : " box-em-breve");

  if (box.ativo) {
    el.href = `/app/${box.id}`;
  } else {
    // `aria-disabled` e não `disabled`: o cartão continua alcançável por Tab e o leitor
    // de tela anuncia o motivo. Um cartão que some da ordem de tabulação não é
    // "desabilitado", é invisível para quem navega por teclado.
    el.setAttribute("role", "link");
    el.setAttribute("aria-disabled", "true");
    el.tabIndex = 0;
  }

  const ico = document.createElement("div");
  ico.className = "box-icone";
  ico.innerHTML = ICONES[box.icone] || ICONES.generico;
  ico.setAttribute("aria-hidden", "true");   // o nome acessível vem do texto abaixo

  const tit = document.createElement("h3");
  tit.textContent = box.titulo;

  const sub = document.createElement("p");
  sub.className = "box-sub";
  sub.textContent = box.subtitulo;

  el.append(ico, tit, sub);

  if (!box.ativo) {
    const m = document.createElement("p");
    m.className = "box-motivo";
    // O motivo é o que o cartão diz NO LUGAR da ação. Um botão morto sem explicação é
    // pior que um botão ausente: a pessoa clica, nada acontece, e ela conclui que o
    // programa está quebrado.
    m.textContent = box.motivo;
    const selo = document.createElement("span");
    selo.className = "box-selo";
    selo.textContent = "em breve";
    el.append(selo, m);
    el.setAttribute("aria-label", `${box.titulo} — em breve. ${box.motivo}`);
  }
  return el;
}

async function sair() {
  if (!confirm("Encerrar o FPSO_Siz?\n\nO que já foi exportado continua salvo.")) return;
  status("Encerrando…");
  try {
    await fetch("/api/parar", { method: "POST" });
  } catch (_) { /* já caiu — é o desfecho esperado */ }
  document.body.innerHTML =
    '<p style="padding:24px;font:14px system-ui">FPSO_Siz encerrado. ' +
    "Pode fechar esta aba.</p>";
}

function iniciar() {
  const boxes = (window.__INICIAL__ || {}).boxes || [];
  q("grade-boxes").replaceChildren(...boxes.map(cartao));
  q("btn-sair").addEventListener("click", sair);

  const prontos = boxes.filter((b) => b.ativo).length;
  status(`${prontos} de ${boxes.length} aplicações disponíveis.`);
}

// Uma exceção não tratada deixaria a tela parada em "Carregando…" sem dizer por quê.
// Os DOIS eventos, como em app.js: `error` não pega promessa rejeitada, e `sair()` é
// `async` — uma falha lá dentro sumiria sem deixar nada na barra, que é exatamente o
// desfecho que este par de guardas existe para impedir.
window.addEventListener("error", (e) =>
  status(`Falha na interface: ${e.message}`, false));
window.addEventListener("unhandledrejection", (e) =>
  status(`Falha na interface: ${e.reason}`, false));

iniciar();
