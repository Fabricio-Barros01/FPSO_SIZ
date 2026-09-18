/*
 * Ícones dos cartões do menu, em SVG escrito à mão.
 *
 * Por que não uma fonte de ícones ou um CDN: o programa é distribuído como executável
 * autocontido e roda offline — qualquer recurso de rede viraria um retângulo vazio na
 * máquina de quem o recebeu, sem erro visível. Sete desenhos de vinte linhas custam
 * menos que essa classe de falha.
 *
 * Todos partilham a mesma caixa (24×24), traço `currentColor` e nenhum preenchimento,
 * para que o CSS controle cor e tamanho num lugar só.
 *
 * `stroke-width` 1.5 é o que o design system "Industry" especifica (é a espessura do
 * Lucide, que ele adota) — estes desenhos estavam em 1.6, e a diferença aparecia quando
 * um ícone ficava ao lado de um traço do sistema.
 *
 * O que NÃO se faz é trocar estes desenhos por ícones do Lucide, e a razão é que não há
 * por quê trocar: o Lucide não tem separador trifásico, vaso knockout, tratador
 * eletrostático nem curva composta de Pinch. O que existiria seria uma engrenagem para
 * a bomba e um cilindro para os cinco vasos — sete cartões que o usuário não distingue
 * de relance, que é exatamente o trabalho que o ícone faz aqui. Do Lucide se adota a
 * GRAMÁTICA (caixa 24×24, traço 1.5, pontas e junções redondas), não o acervo.
 */

"use strict";

const _svg = (corpo) =>
  `<svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="currentColor"
        stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${corpo}</svg>`;

const ICONES = {
  // Vaso horizontal com duas interfaces: as três fases do separador trifásico.
  separador3f: _svg(`
    <rect x="2.5" y="7" width="19" height="10" rx="5"/>
    <path d="M2.6 13.2h18.8"/>
    <path d="M3.4 15.6h17.2" stroke-dasharray="2 1.6"/>`),

  // O mesmo vaso com uma interface só: gás e líquido.
  knockout2f: _svg(`
    <rect x="2.5" y="7" width="19" height="10" rx="5"/>
    <path d="M2.6 12h18.8"/>`),

  // Voluta e eixo.
  bomba: _svg(`
    <circle cx="11" cy="13" r="6"/>
    <path d="M11 7V4h6"/>
    <path d="M17 13h4"/>
    <circle cx="11" cy="13" r="1.6"/>`),

  // Casco e tubos, com as duas correntes em contracorrente.
  trocador: _svg(`
    <rect x="2.5" y="8" width="19" height="8" rx="2"/>
    <path d="M2.5 12h19"/>
    <path d="M6 8V5m12 11v3"/>`),

  // Vaso com os eletrodos e o campo entre eles.
  eletrostatico: _svg(`
    <rect x="2.5" y="7" width="19" height="10" rx="5"/>
    <path d="M8 10v4M16 10v4"/>
    <path d="M10 12h4" stroke-dasharray="1.4 1.4"/>`),

  // As duas curvas compostas e o aperto entre elas — a figura da própria Análise Pinch
  // (Kemp, Figura 2.6). Não é equipamento nenhum, e é essa a informação: a curva quente
  // descendo, a fria subindo, e o ponto em que se aproximam ao máximo, marcado.
  pinch: _svg(`
    <path d="M3 17c3.2 0 4.6-3.1 7.4-3.1"/>
    <path d="M10.4 13.9c2.9 0 4.4 3.1 7.6 3.1"/>
    <path d="M4.6 10.1c3.2 0 4.6-3.1 7.4-3.1"/>
    <path d="M12 7c2.9 0 4.4 3.1 7.4 3.1"/>
    <path d="M11.2 13.5V10.6" stroke-dasharray="1.3 1.2"/>
    <circle cx="11.2" cy="13.7" r="1"/>`),

  // Malha fechada: medição, controlador e válvula.
  controle: _svg(`
    <circle cx="6" cy="12" r="2.4"/>
    <rect x="10" y="9.6" width="4.8" height="4.8" rx="1"/>
    <path d="M18 9.6l3 2.4-3 2.4z"/>
    <path d="M8.4 12h1.6M14.8 12H18"/>
    <path d="M6 14.4v3.6h13.5V14.4" stroke-dasharray="2 1.6"/>`),

  // Reserva: um box do catálogo que peça um ícone inexistente ainda desenha algo, em
  // vez de deixar um buraco silencioso no cartão.
  generico: _svg(`
    <rect x="3.5" y="3.5" width="17" height="17" rx="3"/>
    <path d="M8 12h8"/>`),
};
