// Vendorizado do handoff de design — References/FPSO SIZ UI mockups/models/separador.js
//
// CÓPIA. A origem é o artboard do Claude Design; alterar só esta cópia faz o app
// divergir do handoff sem nada denunciar.
//
// `import ... from 'three'` resolve pelo mapa de importação de `casca.html`, que aponta
// para `/vendor/` — local, porque o programa empacotado abre sem internet.
// Separador trifásico horizontal — modelo paramétrico.
// Geometria e nomenclatura portadas de app/src/desenho/vaso.jl (elevação e corte):
// casco entre costuras Lss, tampos elípticos 2:1 (head_depth = d/4), placa vertedora
// em Leff, extrator de névoa, defletor de entrada, bocais nomeados pelas fases.
// Cores = app/src/formato.jl (ACO, GAS/OLEO/AGUA_ZONA, INTERNO).
import * as THREE from 'three';

// Os tons de aço são as cores de formato.jl (ACO #5c636c, INTERNO #4a515a) clareadas:
// sem mapa de ambiente na cena, o hex original renderiza quase preto.
export const CORES = {
  aco: 0xa8b0b8, interno: 0x8b939c, gas: 0xd9e2ec, oleo: 0x4a3116, agua: 0x4484ba,
  selim: 0x767d85,
};

const mat = (name, color, o = {}) => Object.assign(
  new THREE.MeshStandardMaterial({ color, roughness: 0.55, metalness: 0.25, ...o }),
  { name });

function bandaShape(R, y0, y1, seg = 40, meia = false) {
  // Faixa horizontal do círculo de raio R (centro na origem), entre y0 e y1.
  // meia: só a metade afastada da câmera, para o corte deixar os internos à vista.
  const pts = [];
  const xAt = (y) => Math.sqrt(Math.max(R * R - y * y, 0));
  for (let i = 0; i <= seg; i++) {           // borda direita (ou plano de corte), subindo
    const y = y0 + (y1 - y0) * (i / seg);
    pts.push(new THREE.Vector2(meia ? 0 : xAt(y), y));
  }
  for (let i = seg; i >= 0; i--) {           // borda esquerda, descendo
    const y = y0 + (y1 - y0) * (i / seg);
    pts.push(new THREE.Vector2(-xAt(y), y));
  }
  return new THREE.Shape(pts);
}

function faixa(name, material, R, y0, y1, comp, meia) {
  const g = new THREE.ExtrudeGeometry(bandaShape(R, y0, y1, 40, meia),
    { depth: comp, bevelEnabled: false, curveSegments: 48 });
  g.rotateY(Math.PI / 2);                    // extrusão passa a correr em +x
  g.translate(-comp / 2, 0, 0);
  const m = new THREE.Mesh(g, material);
  m.name = name;
  return m;
}

function tampo(name, material, R, profundidade, sinal) {
  // Tampo elíptico 2:1: hemisfério achatado até profundidade = d/4.
  const g = new THREE.SphereGeometry(R, 48, 24, 0, Math.PI * 2, 0, Math.PI / 2);
  g.rotateZ(-sinal * Math.PI / 2);
  g.scale(profundidade / R, 1, 1);
  const m = new THREE.Mesh(g, material);
  m.name = name;
  return m;
}

function bocal(name, material, R, x, dir, dn, alt) {
  const g = new THREE.Group();
  g.name = name;
  const tubo = new THREE.Mesh(new THREE.CylinderGeometry(dn / 2, dn / 2, alt, 24), material);
  tubo.name = name + '_tubo';
  const flange = new THREE.Mesh(new THREE.CylinderGeometry(dn * 0.85, dn * 0.85, dn * 0.18, 24), material);
  flange.name = name + '_flange';
  flange.position.y = alt / 2;
  g.add(tubo, flange);
  g.position.set(x, dir * (R + alt / 2 - dn * 0.15), 0);
  if (dir < 0) g.rotation.z = Math.PI;
  return g;
}

/**
 * @param {object} o  d (m), lss (m), leff (m), beta (hₒ/d), nivel (fração cheia),
 *                    tipo 'separador' | 'knockout' | 'tratador' | 'dinamico',
 *                    lod 'esquematico' | 'detalhado', fases true/false
 */
export function buildSeparador(o = {}) {
  const d = o.d ?? 5.65, lss = o.lss ?? 21.78, leff = o.leff ?? 16.34;
  const tipo = o.tipo ?? 'separador';
  const beta = o.beta ?? 0.03;
  // O tratador eletrostático é cheio de líquido (vaso.jl: não tem céu de gás);
  // separador e knockout trabalham meio cheios.
  const nivelFrac = o.nivel ?? (tipo === 'tratador' ? 1.0 : 0.5);
  const detalhado = (o.lod ?? 'detalhado') === 'detalhado';
  const R = d / 2, hd = d / 4;

  const mAco = mat('aco_carbono', CORES.aco, { roughness: 0.42, metalness: 0.3 });
  const mCasco = mat('casco_aco', CORES.aco, {
    roughness: 0.4, metalness: 0.25, transparent: true, opacity: 0.3,
    side: THREE.DoubleSide, depthWrite: false });
  const mInterno = mat('interno', CORES.interno, { roughness: 0.55, metalness: 0.28 });
  const mSelim = mat('selim', CORES.selim, { roughness: 0.8, metalness: 0.1 });
  const mGas = mat('fase_gas', CORES.gas, { transparent: true, opacity: 0.35, roughness: 0.9, metalness: 0 });
  // No tratador o líquido ocupa o vaso inteiro: além de meia-seção, as fases entram
  // mais translúcidas para as grades e a placa vertedora continuarem legíveis.
  const opacLiq = tipo === 'tratador' ? 0.46 : 0.88;
  const mOleo = mat('fase_oleo', CORES.oleo, { transparent: true, opacity: opacLiq, roughness: 0.75, metalness: 0, side: THREE.DoubleSide, depthWrite: false });
  const mAgua = mat('fase_agua', CORES.agua, { transparent: true, opacity: opacLiq, roughness: 0.7, metalness: 0, side: THREE.DoubleSide, depthWrite: false });

  const grupo = new THREE.Group();
  grupo.name = tipo === 'knockout' ? 'vaso_knockout_bifasico'
    : tipo === 'tratador' ? 'tratador_eletrostatico'
    : tipo === 'dinamico' ? 'separador_dinamico' : 'separador_trifasico';

  // Casco: meia-casca aberta em cima para o corte ficar legível quando há fases.
  const cascoGeo = new THREE.CylinderGeometry(R, R, lss, 64, 1, true);
  cascoGeo.rotateZ(Math.PI / 2);
  const casco = new THREE.Mesh(cascoGeo, mCasco);
  casco.name = 'casco';
  grupo.add(casco);

  // Costuras casco/tampo, como as linhas pontilhadas da elevação.
  for (const s of [-1, 1]) {
    const anel = new THREE.Mesh(new THREE.TorusGeometry(R, d * 0.006, 8, 64), mAco);
    anel.name = 'costura_' + (s < 0 ? 'a' : 'b');
    anel.rotation.y = Math.PI / 2;
    anel.position.x = s * lss / 2;
    grupo.add(anel);
  }

  grupo.add(tampo('tampo_entrada', mCasco, R, hd, -1).translateX(-lss / 2));
  grupo.add(tampo('tampo_saida', mCasco, R, hd, 1).translateX(lss / 2));

  // A placa vertedora divide o vaso em dois compartimentos: a montante decantam água e
  // óleo; a jusante só passa óleo, que se acumula num nível abaixo do topo da placa.
  const nivel = -R + nivelFrac * d;
  const xPlaca = -lss / 2 + leff;
  const compMont = leff - 0.01, compJus = lss - leff - 0.01;
  const nivelJusante = nivel - d * 0.09;

  if (o.fases !== false) {
    const r = R - 0.012;
    if (tipo === 'knockout') {
      // Bifásico: uma interface só — líquido embaixo, gás no que sobra.
      grupo.add(faixa('fase_liquido', mOleo, r, -R, nivel, lss - 0.02));
      grupo.add(faixa('ceu_de_gas', mGas, r, nivel, R - 0.01, lss - 0.02));
    } else if (tipo === 'tratador') {
      // Cheio de líquido: emulsão/óleo sobre a água livre, sem céu de gás.
      const yAgua = -R + d * 0.12;
      grupo.add(faixa('agua_livre', mAgua, r, -R, yAgua, lss - 0.02, true));
      grupo.add(faixa('oleo_tratado', mOleo, r, yAgua, R - 0.01, lss - 0.02, true));
    } else {
      const hAgua = (0.5 - beta) * d, hOleo = beta * d;
      const y0 = -R, yAgua = -R + hAgua, yOleo = Math.max(yAgua + hOleo, yAgua + 0.02);
      const xMont = -lss / 2 + compMont / 2 + 0.005;
      const xJus = xPlaca + compJus / 2 + 0.005;
      grupo.add(faixa('fase_agua', mAgua, r, y0, yAgua, compMont).translateX(xMont));
      grupo.add(faixa('fase_oleo', mOleo, r, yAgua, yOleo, compMont).translateX(xMont));
      grupo.add(faixa('ceu_de_gas', mGas, r, nivel, R - 0.01, compMont).translateX(xMont));
      // Jusante da placa: óleo do fundo até o nível mais baixo, e gás acima.
      grupo.add(faixa('oleo_apos_vertedora', mOleo, r, y0, nivelJusante, compJus).translateX(xJus));
      grupo.add(faixa('ceu_de_gas_jusante', mGas, r, nivelJusante, R - 0.01, compJus).translateX(xJus));
    }
  }

  // Selins de apoio, a 0,2 Lss de cada costura.
  for (const s of [-1, 1]) {
    const sel = new THREE.Mesh(new THREE.BoxGeometry(d * 0.22, R * 0.55, d * 0.9), mSelim);
    sel.name = 'selim_' + (s < 0 ? 'a' : 'b');
    sel.position.set(s * lss * 0.3, -R - R * 0.275, 0);
    grupo.add(sel);
  }

  // Bocais nomeados pelas fases que o vaso tem (vaso.jl: bocais!).
  const dn = d * 0.11, alt = d * 0.16;
  grupo.add(bocal('bocal_entrada', mAco, R, -lss * 0.44, 1, dn * 1.15, alt));
  if (tipo === 'knockout') {
    grupo.add(bocal('bocal_saida_gas', mAco, R, lss * 0.44, 1, dn, alt));
    grupo.add(bocal('bocal_saida_liquido', mAco, R, -lss * 0.42, -1, dn * 0.8, alt));
  } else if (tipo === 'tratador') {
    grupo.add(bocal('bocal_saida_oleo', mAco, R, lss * 0.44, 1, dn, alt));
    grupo.add(bocal('bocal_saida_agua', mAco, R, -lss * 0.42, -1, dn * 0.8, alt));
  } else {
    grupo.add(bocal('bocal_saida_gas', mAco, R, lss * 0.44, 1, dn, alt));
    grupo.add(bocal('bocal_saida_agua', mAco, R, -lss * 0.42, -1, dn * 0.8, alt));
    grupo.add(bocal('bocal_saida_oleo', mAco, R, lss * 0.46, -1, dn * 0.8, alt));
  }

  if (detalhado) {
    const temGas = tipo !== 'tratador';
    const temVertedora = tipo === 'separador' || tipo === 'dinamico' || tipo === 'tratador';

    if (temVertedora) {
      // Placa vertedora em Leff, até o nível de líquido (vaso.jl: internos!).
      const placa = faixa('placa_vertedora', mInterno, R - 0.02, -R + 0.02, nivel, d * 0.024);
      placa.position.x = xPlaca;
      grupo.add(placa);
    }

    if (temGas) {
      // Defletor de entrada e extrator de névoa: internos do céu de gás. Um vaso cheio
      // de líquido não os tem — desenhá-los prometeria um interno inexistente.
      const defl = faixa('defletor_entrada', mInterno, R - 0.02, 0, R * 0.8, d * 0.02);
      defl.position.x = -lss / 2 + lss * 0.07;
      grupo.add(defl);

      const ext = new THREE.Mesh(
        new THREE.BoxGeometry(lss * 0.11, d * 0.18, d * 0.62),
        mat('extrator_nevoa', CORES.aco, { roughness: 0.9, metalness: 0.2 }));
      ext.name = 'extrator_nevoa';
      ext.position.set(-lss / 2 + lss * 0.875, -R + d * 0.79, 0);
      grupo.add(ext);
    }

    if (tipo === 'tratador') {
      // Grades de eletrodos e as buchas passantes: o campo elétrico é o que coalesce a
      // emulsão (§4.7-4.9), e é o único interno que este vaso tem.
      const mEletrodo = mat('eletrodo', 0xb9a06a, { roughness: 0.35, metalness: 0.4 });
      for (const [i, yF] of [0.55, 0.78].entries()) {
        const grade = new THREE.Group();
        grade.name = 'grade_eletrodo_' + (i + 1);
        for (let k = 0; k < 9; k++) {
          const barra = new THREE.Mesh(
            new THREE.CylinderGeometry(d * 0.012, d * 0.012, d * 0.62, 12), mEletrodo);
          barra.name = 'eletrodo_' + (i + 1) + '_' + (k + 1);
          barra.rotation.x = Math.PI / 2;
          barra.position.set(-lss * 0.28 + k * (lss * 0.56 / 8), -R + d * yF, 0);
          grade.add(barra);
        }
        const bucha = new THREE.Mesh(
          new THREE.CylinderGeometry(d * 0.03, d * 0.03, d * 0.2, 16), mEletrodo);
        bucha.name = 'bucha_passante_' + (i + 1);
        bucha.position.set(-lss * 0.28 + i * lss * 0.56, R + d * 0.06, 0);
        grade.add(bucha);
        grupo.add(grade);
      }
    }

    if (tipo === 'dinamico') {
      // As três válvulas de controle que as malhas PI manipulam (§3.2).
      const mAtuador = mat('atuador', CORES.interno, { roughness: 0.6, metalness: 0.25 });
      const valvulas = [
        ['valvula_gas', lss * 0.44, R + alt * 1.5],
        ['valvula_oleo', lss * 0.46, -R - alt * 1.5],
        ['valvula_agua', -lss * 0.42, -R - alt * 1.5],
      ];
      for (const [nome, x, y] of valvulas) {
        const corpo = new THREE.Mesh(new THREE.SphereGeometry(d * 0.075, 20, 14), mAco);
        corpo.name = nome + '_corpo';
        corpo.position.set(x, y, 0);
        const atuador = new THREE.Mesh(
          new THREE.CylinderGeometry(d * 0.055, d * 0.055, d * 0.1, 16), mAtuador);
        atuador.name = nome + '_atuador';
        atuador.position.set(x, y + (y > 0 ? d * 0.1 : -d * 0.1), 0);
        grupo.add(corpo, atuador);
      }
    }

    // Bocal de visita no topo.
    grupo.add(bocal('boca_de_visita', mAco, R, 0, 1, d * 0.16, alt * 0.8));
  }

  grupo.traverse((n) => { if (n.isMesh) { n.castShadow = true; n.receiveShadow = true; } });
  const caixa = new THREE.Box3().setFromObject(grupo);
  grupo.position.y -= caixa.min.y;
  return grupo;
}
