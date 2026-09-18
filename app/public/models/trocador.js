// Vendorizado do handoff de design — References/FPSO SIZ UI mockups/models/trocador.js
//
// CÓPIA. A origem é o artboard do Claude Design; alterar só esta cópia faz o app
// divergir do handoff sem nada denunciar.
//
// `import ... from 'three'` resolve pelo mapa de importação de `casca.html`, que aponta
// para `/vendor/` — local, porque o programa empacotado abre sem internet.
// Trocador casco-e-tubos — modelo paramétrico.
// Papel na tela: a figura da área principal, que em app/src/desenho/figuras.jl é o
// "corte do casco" (svg_trocador) e responde ao cursor de tubos por passe.
// Cores = app/src/formato.jl, clareadas para renderizar sem mapa de ambiente.
import * as THREE from 'three';

export const CORES = { aco: 0xa8b0b8, tubo: 0xb9a06a, interno: 0x9aa2ab, quente: 0x9c5b3a, frio: 0x4484ba, base: 0x767d85 };

const mat = (name, color, o = {}) => Object.assign(
  new THREE.MeshStandardMaterial({ color, roughness: 0.5, metalness: 0.3, ...o }),
  { name });

// Rede triangular de tubos dentro do diâmetro do feixe (passo 1,25·d_o).
function posicoesTubos(nAlvo, rFeixe, passo) {
  const pos = [];
  const linhas = Math.ceil(2 * rFeixe / (passo * Math.sqrt(3) / 2));
  for (let i = -linhas; i <= linhas && pos.length < nAlvo; i++) {
    const y = i * passo * Math.sqrt(3) / 2;
    const desloc = (Math.abs(i) % 2) * passo / 2;
    const cols = Math.ceil(2 * rFeixe / passo);
    for (let j = -cols; j <= cols && pos.length < nAlvo; j++) {
      const z = j * passo + desloc;
      if (Math.hypot(y, z) <= rFeixe - passo * 0.35) pos.push([y, z]);
    }
  }
  return pos;
}

/**
 * @param {object} o  nTubos (por passe), passes (1|2), l (m, comprimento do tubo),
 *                    dCasco (m), dTubo (m, externo), lod 'esquematico'|'detalhado'
 */
export function buildTrocador(o = {}) {
  const passes = o.passes ?? 2;
  const nTubos = Math.max(4, Math.round(o.nTubos ?? 120)) * passes;
  const L = o.l ?? 6.0;
  const dTubo = o.dTubo ?? 0.01905;
  const passo = dTubo * 1.25;
  const detalhado = (o.lod ?? 'detalhado') === 'detalhado';
  // Diâmetro do casco: o feixe ocupa ~65 % da área do casco (Branan), com folga mínima.
  const rFeixe = Math.max(passo * 1.6, Math.sqrt(nTubos / 0.9) * passo / 2);
  const rCasco = o.dCasco ? o.dCasco / 2 : rFeixe * 1.12 + dTubo;

  const mAco = mat('aco_carbono', CORES.aco, { roughness: 0.45, metalness: 0.3 });
  const mCasco = mat('casco_aco', CORES.aco, {
    roughness: 0.4, metalness: 0.25, transparent: true, opacity: 0.26,
    side: THREE.DoubleSide, depthWrite: false });
  const mTubo = mat('tubo_latao_admiralty', CORES.tubo, { roughness: 0.35, metalness: 0.45 });
  const mChicana = mat('chicana', CORES.interno, { roughness: 0.6, metalness: 0.25 });
  const mBase = mat('selim', CORES.base, { roughness: 0.85, metalness: 0.12 });

  const g = new THREE.Group();
  g.name = 'trocador_casco_e_tubos';

  const cascoGeo = new THREE.CylinderGeometry(rCasco, rCasco, L, 64, 1, true);
  cascoGeo.rotateZ(Math.PI / 2);
  const casco = new THREE.Mesh(cascoGeo, mCasco);
  casco.name = 'casco';
  g.add(casco);

  // Espelhos (tube sheets) e o carretel com a partição de passe.
  for (const [i, s] of [-1, 1].entries()) {
    const esp = new THREE.Mesh(new THREE.CylinderGeometry(rCasco, rCasco, rCasco * 0.09, 48), mAco);
    esp.name = 'espelho_' + (i + 1);
    esp.rotation.z = Math.PI / 2;
    esp.position.x = s * L / 2;
    g.add(esp);
  }
  const carretel = new THREE.Mesh(
    new THREE.CylinderGeometry(rCasco, rCasco, rCasco * 1.2, 48, 1, true), mCasco);
  carretel.name = 'carretel';
  carretel.rotation.z = Math.PI / 2;
  carretel.position.x = -L / 2 - rCasco * 0.65;
  g.add(carretel);
  const tampaCarretel = new THREE.Mesh(
    new THREE.SphereGeometry(rCasco, 40, 20, 0, Math.PI * 2, 0, Math.PI / 2), mCasco);
  tampaCarretel.name = 'tampa_do_carretel';
  tampaCarretel.geometry.rotateZ(Math.PI / 2);
  tampaCarretel.geometry.scale(rCasco / 4 / rCasco, 1, 1);
  tampaCarretel.position.x = -L / 2 - rCasco * 1.25;
  g.add(tampaCarretel);

  if (passes === 2) {
    const part = new THREE.Mesh(
      new THREE.BoxGeometry(rCasco * 1.2, rCasco * 1.94, rCasco * 0.06), mAco);
    part.name = 'particao_de_passe';
    part.rotation.y = Math.PI / 2;
    part.position.set(-L / 2 - rCasco * 0.65, 0, 0);
    g.add(part);
  }

  // Feixe: um mesh instanciado, com os tubos do passe de ida e do de volta separados
  // pela partição (metade de cima / metade de baixo) quando há dois passes.
  const pos = posicoesTubos(nTubos, rFeixe, passo);
  const tuboGeo = new THREE.CylinderGeometry(dTubo / 2, dTubo / 2, L, 12, 1, false);
  tuboGeo.rotateZ(Math.PI / 2);
  const feixe = new THREE.InstancedMesh(tuboGeo, mTubo, pos.length);
  feixe.name = 'feixe_de_tubos';
  const m4 = new THREE.Matrix4();
  pos.forEach(([y, z], i) => {
    m4.makeTranslation(0, y, z);
    feixe.setMatrixAt(i, m4);
  });
  feixe.castShadow = true;
  feixe.receiveShadow = true;
  g.add(feixe);

  // Bocais: casco (quente, entra em cima na saída oposta) e tubos (frio, no carretel).
  const bocal = (name, material, r, alt, pos2, rot) => {
    const grp = new THREE.Group();
    grp.name = name;
    const tubo = new THREE.Mesh(new THREE.CylinderGeometry(r, r, alt, 24), material);
    tubo.name = name + '_tubo';
    const fl = new THREE.Mesh(new THREE.CylinderGeometry(r * 1.5, r * 1.5, r * 0.32, 24), material);
    fl.name = name + '_flange';
    fl.position.y = alt / 2;
    grp.add(tubo, fl);
    grp.position.set(...pos2);
    if (rot) grp.rotation.set(...rot);
    return grp;
  };
  const rb = rCasco * 0.22, ab = rCasco * 0.5;
  g.add(bocal('bocal_casco_entrada', mAco, rb, ab, [L * 0.38, rCasco + ab / 2, 0]));
  g.add(bocal('bocal_casco_saida', mAco, rb, ab, [-L * 0.34, -rCasco - ab / 2, 0], [Math.PI, 0, 0]));
  g.add(bocal('bocal_tubos_entrada', mAco, rb * 0.9, ab, [-L / 2 - rCasco * 0.65, -rCasco - ab / 2, 0], [Math.PI, 0, 0]));
  g.add(bocal('bocal_tubos_saida', mAco, rb * 0.9, ab, [-L / 2 - rCasco * 0.65, rCasco + ab / 2, 0]));

  if (detalhado) {
    // Chicanas de corte 25 % — a geometria que o Bell-Delaware consome.
    const nCh = Math.max(3, Math.round(L / (rCasco * 2.4)));
    for (let i = 1; i <= nCh; i++) {
      const x = -L / 2 + i * L / (nCh + 1);
      const corte = new THREE.Mesh(
        new THREE.CylinderGeometry(rCasco * 0.985, rCasco * 0.985, rCasco * 0.05, 48, 1, false, 0, Math.PI * 1.5),
        mChicana);
      corte.name = 'chicana_' + i;
      corte.rotation.z = Math.PI / 2;
      corte.rotation.x = (i % 2) * Math.PI;
      corte.position.x = x;
      g.add(corte);
    }
  }

  for (const s of [-0.28, 0.3]) {
    const sel = new THREE.Mesh(
      new THREE.BoxGeometry(rCasco * 0.5, rCasco * 0.5, rCasco * 1.8), mBase);
    sel.name = 'selim_' + (s < 0 ? 'a' : 'b');
    sel.position.set(s * L, -rCasco - rCasco * 0.25, 0);
    g.add(sel);
  }

  g.traverse((n) => { if (n.isMesh) { n.castShadow = true; n.receiveShadow = true; } });
  const caixa = new THREE.Box3().setFromObject(g);
  g.position.y -= caixa.min.y;
  const c = new THREE.Box3().setFromObject(g).getCenter(new THREE.Vector3());
  g.position.x -= c.x;
  return g;
}
