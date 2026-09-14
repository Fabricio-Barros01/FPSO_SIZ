/*
 * FPSO_Siz — a tela DINÂMICA (Song 2023).
 *
 * Autônoma (não compartilha estado com app.js). As mesmas regras valem:
 *
 * 1. NENHUM CAMPO É ESCRITO À MÃO. O formulário nasce de `window.__INICIAL__.campos`,
 *    que vem dos `ParameterSpec` do core. Um parâmetro novo entra por descritor, não por
 *    código aqui.
 * 2. Os valores viajam como NÚMERO JSON (o input é type=number, cujo `.value` é sempre
 *    decimal com ponto), e o servidor os recebe como `Float64`. Sem locale, sem
 *    ambiguidade — a única diferença para app.js, que manda texto PT-BR.
 * 3. Os gráficos vêm do servidor já em SVG, agrupados por eixo; aqui só se injetam.
 */
"use strict";
(function () {
  const q = (id) => document.getElementById(id);
  const INI = window.__INICIAL__ || {};
  const box = INI.box || "";
  const campos = (INI.esquema && INI.esquema.campos) || [];

  function status(texto, ok = true) {
    const el = q("status");
    if (!el) return;
    el.textContent = texto;
    el.classList.toggle("ruim", !ok);
  }

  function montarForm() {
    const tbody = q("form-dinamico").querySelector("tbody");
    tbody.innerHTML = "";
    for (const c of campos) {
      const tr = document.createElement("tr");
      tr.className = "campo" + (c.advanced ? " avancado" : "");
      if (c.advanced) tr.hidden = true;
      const th = document.createElement("th");
      th.textContent = c.label + (c.unit && c.unit !== "–" ? " (" + c.unit + ")" : "");
      if (c.note) th.title = c.note;
      const td = document.createElement("td");
      const inp = document.createElement("input");
      inp.type = "number";
      inp.step = "any";
      inp.value = c.default;
      inp.min = c.min;
      inp.max = c.max;
      inp.dataset.key = c.key;
      inp.setAttribute("aria-label", c.label);
      td.appendChild(inp);
      tr.appendChild(th);
      tr.appendChild(td);
      tbody.appendChild(tr);
    }
  }

  function coletar() {
    const valores = {};
    for (const inp of q("form-dinamico").querySelectorAll("input[data-key]")) {
      const v = parseFloat(inp.value);
      if (Number.isFinite(v)) valores[inp.dataset.key] = v;
    }
    return valores;
  }

  function toggleAvancado() {
    const mostrar = q("chk-avancado").checked;
    for (const tr of q("form-dinamico").querySelectorAll("tr.avancado")) {
      tr.hidden = !mostrar;
    }
  }

  function f(x, n) {
    return typeof x === "number" && isFinite(x) ? x.toFixed(n === undefined ? 2 : n) : "—";
  }

  function render(data) {
    const dl = q("resumo-dinamico");
    dl.innerHTML = "";
    const r = data.resumo || {};
    if (data.ok && Object.keys(r).length) {
      const linha = (rot, val) => {
        const dt = document.createElement("dt");
        dt.textContent = rot;
        const dd = document.createElement("dd");
        dd.textContent = val;
        dl.appendChild(dt);
        dl.appendChild(dd);
      };
      const reg = r.regime || {};
      const marca = (ok) => (ok ? " ✓" : "");
      linha("Modo", "malha " + (r.malha || "—"));
      linha("Horizonte", f(r.horizonte, 0) + " s");
      linha("Pressão final", f(r.pressao_kpa, 1) + " kPa" + marca(reg.pressao));
      linha("Nível de água", f(r.h_agua, 3) + " m" + marca(reg.agua));
      linha("Nível de óleo", f(r.h_oleo, 3) + " m" + marca(reg.oleo));
      linha("Aberturas (óleo/água/gás)",
        f(r.ab_oleo, 3) + " / " + f(r.ab_agua, 3) + " / " + f(r.ab_gas, 3));
      linha("Água no óleo φ (esq./dir.)",
        f(r.phi_esq, 4) + " / " + f(r.phi_dir, 4) + marca(reg.phi));
      linha("Folga de CFL (mín.)", f(r.folga_cfl, 1) + "×");
      linha("Regime permanente", r.regime_todos ? "atingido" : "transitório");
    }

    const area = q("graficos-dinamico");
    area.innerHTML = "";
    const gs = data.graficos || [];
    if (!gs.length) {
      area.innerHTML = '<p class="dica">' + (data.status || "Sem resultado.") + "</p>";
      return;
    }
    for (const svg of gs) {
      const div = document.createElement("div");
      div.className = "grafico";
      div.innerHTML = svg;
      area.appendChild(div);
    }
  }

  async function simular() {
    const btn = q("btn-simular");
    btn.disabled = true;
    status("Simulando…");
    try {
      const resp = await fetch("/api/" + box + "/simular", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ valores: coletar(), malha_fechada: q("chk-malha").checked }),
      });
      const data = await resp.json();
      render(data);
      status(data.status || "", data.status_ok !== false);
    } catch (e) {
      status("Falha de rede ao simular: " + e, false);
    } finally {
      btn.disabled = false;
    }
  }

  async function sair() {
    try {
      await fetch("/api/parar", { method: "POST" });
    } catch (e) {
      /* o servidor pode cair antes de responder — esperado */
    }
    status("Programa encerrado. Pode fechar a aba.");
  }

  q("rotulo-titulo").textContent = INI.titulo || "";
  montarForm();
  q("chk-avancado").addEventListener("change", toggleAvancado);
  q("btn-simular").addEventListener("click", simular);
  q("btn-sair").addEventListener("click", sair);
  status("Pronto. Ajuste os parâmetros e clique em Simular.");
})();
