// Vendorizado do handoff de design — References/FPSO SIZ UI mockups/models/bomba.js
//
// CÓPIA. A origem é o artboard do Claude Design; alterar só esta cópia faz o app
// divergir do handoff sem nada denunciar.
//
// `import ... from 'three'` resolve pelo mapa de importação de `casca.html`, que aponta
// para `/vendor/` — local, porque o programa empacotado abre sem internet.
// Bomba centrífuga de transferência — modelo paramétrico no DN da linha.
// A grandeza que a tela varre é o diâmetro nominal (src/sizing/pump/moran.jl,
// sweep_axis); aqui ele dimensiona bocais, voluta e, no LOD detalhado, o rotor.
// Cores = app/src/formato.jl.
import * as THREE from 'three';

// Tons de formato.jl (ACO #5c636c, INTERNO #4a515a) clareados: a cena não tem mapa de
// ambiente, e o hex original renderiza quase preto.
export const CORES = { aco: 0xa8b0b8, interno: 0x9aa2ab, base: 0x767d85, oleo: 0xa47938 };

const mat = (name, color, o = {}) => Object.assign(
  new THREE.MeshStandardMaterial({ color, roughness: 0.5, metalness: 0.3, ...o }),
  { name });

function flange(name, material, r, esp) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, esp, 28), material);
  m.name = name;
  return m;
}

/** @param {object} o dn (mm), lod 'esquematico'|'detalhado', linha true/false */
export function buildBomba(o = {}) {
  const dn = (o.dn ?? 250) / 1000;                 // m
  const detalhado = (o.lod ?? 'detalhado') === 'detalhado';
  const rSuc = dn / 2, rRec = dn * 0.42;           // recalque um degrau abaixo
  const rVoluta = dn * 1.55, espVoluta = dn * 1.15;

  const mAco = mat('aco_fundido', CORES.aco, { roughness: 0.55, metalness: 0.28 });
  const mUsinado = mat('aco_usinado', CORES.interno, { roughness: 0.32, metalness: 0.35 });
  const mBase = mat('base_metalica', CORES.base, { roughness: 0.85, metalness: 0.15 });

  const g = new THREE.Group();
  g.name = 'bomba_centrifuga';

  // ---- voluta (carcaça em espiral aproximada por toro achatado + corpo)
  const voluta = new THREE.Mesh(
    new THREE.CylinderGeometry(rVoluta, rVoluta * 0.92, espVoluta, 48), mAco);
  voluta.name = 'voluta';
  voluta.rotation.z = Math.PI / 2;
  g.add(voluta);

  const lingua = new THREE.Mesh(
    new THREE.TorusGeometry(rVoluta * 0.98, espVoluta * 0.22, 16, 48, Math.PI * 1.55), mAco);
  lingua.name = 'voluta_espiral';
  lingua.rotation.y = Math.PI / 2;
  g.add(lingua);

  // ---- bocal de sucção: axial, na face da voluta
  const suc = new THREE.Mesh(new THREE.CylinderGeometry(rSuc, rSuc, dn * 1.6, 32), mAco);
  suc.name = 'bocal_succao';
  suc.rotation.z = Math.PI / 2;
  suc.position.x = -espVoluta / 2 - dn * 0.8;
  g.add(suc);
  const fSuc = flange('flange_succao', mAco, rSuc * 1.5, dn * 0.14);
  fSuc.rotation.z = Math.PI / 2;
  fSuc.position.x = -espVoluta / 2 - dn * 1.55;
  g.add(fSuc);

  // ---- bocal de recalque: radial, para cima
  const rec = new THREE.Mesh(new THREE.CylinderGeometry(rRec, rRec, dn * 1.5, 32), mAco);
  rec.name = 'bocal_recalque';
  rec.position.y = rVoluta + dn * 0.7;
  g.add(rec);
  const fRec = flange('flange_recalque', mAco, rRec * 1.55, dn * 0.13);
  fRec.position.y = rVoluta + dn * 1.42;
  g.add(fRec);

  // ---- eixo, selo e mancal
  const eixo = new THREE.Mesh(new THREE.CylinderGeometry(dn * 0.13, dn * 0.13, dn * 2.6, 24), mUsinado);
  eixo.name = 'eixo';
  eixo.rotation.z = Math.PI / 2;
  eixo.position.x = espVoluta / 2 + dn * 1.0;
  g.add(eixo);

  const mancal = new THREE.Mesh(new THREE.CylinderGeometry(dn * 0.46, dn * 0.5, dn * 1.1, 28), mAco);
  mancal.name = 'caixa_de_mancal';
  mancal.rotation.z = Math.PI / 2;
  mancal.position.x = espVoluta / 2 + dn * 0.8;
  g.add(mancal);

  // ---- acionamento
  const motor = new THREE.Mesh(new THREE.CylinderGeometry(dn * 0.95, dn * 0.95, dn * 2.6, 32), mAco);
  motor.name = 'motor';
  motor.rotation.z = Math.PI / 2;
  motor.position.x = espVoluta / 2 + dn * 3.1;
  g.add(motor);
  const caixaLig = new THREE.Mesh(new THREE.BoxGeometry(dn * 0.8, dn * 0.5, dn * 0.7), mAco);
  caixaLig.name = 'caixa_de_ligacao';
  caixaLig.position.set(espVoluta / 2 + dn * 3.1, dn * 1.1, 0);
  g.add(caixaLig);

  const acopl = new THREE.Mesh(new THREE.CylinderGeometry(dn * 0.34, dn * 0.34, dn * 0.5, 24), mUsinado);
  acopl.name = 'acoplamento';
  acopl.rotation.z = Math.PI / 2;
  acopl.position.x = espVoluta / 2 + dn * 1.65;
  g.add(acopl);

  // ---- base metálica
  const base = new THREE.Mesh(new THREE.BoxGeometry(dn * 6.6, dn * 0.3, dn * 2.6), mBase);
  base.name = 'base_metalica';
  base.position.set(espVoluta / 2 + dn * 1.2, -rVoluta - dn * 0.55, 0);
  g.add(base);
  for (const [i, x] of [-dn * 1.2, dn * 3.1].entries()) {
    const pe = new THREE.Mesh(new THREE.BoxGeometry(dn * 0.7, dn * 0.5, dn * 1.6), mBase);
    pe.name = 'pedestal_' + (i + 1);
    pe.position.set(espVoluta / 2 + x, -rVoluta - dn * 0.15, 0);
    g.add(pe);
  }

  if (detalhado) {
    // Rotor fechado visível pela boca de sucção: cubo + cinco pás curvadas.
    const cubo = new THREE.Mesh(new THREE.CylinderGeometry(dn * 0.22, dn * 0.22, espVoluta * 0.5, 24), mUsinado);
    cubo.name = 'cubo_do_rotor';
    cubo.rotation.z = Math.PI / 2;
    g.add(cubo);
    for (let i = 0; i < 5; i++) {
      const pa = new THREE.Mesh(
        new THREE.TorusGeometry(rVoluta * 0.52, espVoluta * 0.1, 8, 20, Math.PI * 0.55), mUsinado);
      pa.name = 'pa_rotor_' + (i + 1);
      pa.rotation.y = Math.PI / 2;
      pa.rotation.z = (i / 5) * Math.PI * 2;
      g.add(pa);
    }
    const disco = new THREE.Mesh(new THREE.CylinderGeometry(rVoluta * 0.72, rVoluta * 0.72, espVoluta * 0.08, 32), mUsinado);
    disco.name = 'disco_do_rotor';
    disco.rotation.z = Math.PI / 2;
    disco.position.x = espVoluta * 0.22;
    g.add(disco);
  }

  if (o.linha !== false) {
    // Trechos de linha nos dois bocais, no DN varrido — é o que muda com o cursor.
    const mLinha = mat('linha_processo', CORES.aco, { roughness: 0.6, metalness: 0.25 });
    const lSuc = new THREE.Mesh(new THREE.CylinderGeometry(rSuc, rSuc, dn * 3.2, 32), mLinha);
    lSuc.name = 'linha_succao';
    lSuc.rotation.z = Math.PI / 2;
    lSuc.position.x = -espVoluta / 2 - dn * 3.2;
    g.add(lSuc);

    const curva = new THREE.Mesh(new THREE.TorusGeometry(dn * 1.1, rRec, 16, 28, Math.PI / 2), mLinha);
    curva.name = 'curva_recalque';
    curva.rotation.y = Math.PI / 2;
    curva.rotation.z = Math.PI;
    curva.position.set(0, rVoluta + dn * 1.42, -dn * 1.1);
    g.add(curva);
    const lRec = new THREE.Mesh(new THREE.CylinderGeometry(rRec, rRec, dn * 3.0, 32), mLinha);
    lRec.name = 'linha_recalque';
    lRec.rotation.x = Math.PI / 2;
    lRec.position.set(0, rVoluta + dn * 2.52, -dn * 1.1 - dn * 1.5 + dn * 1.5);
    lRec.position.z = -dn * 1.1;
    lRec.position.y = rVoluta + dn * 1.42;
    lRec.position.z = -dn * 1.1 - dn * 1.5;
    g.add(lRec);
  }

  g.traverse((n) => { if (n.isMesh) { n.castShadow = true; n.receiveShadow = true; } });
  const caixa = new THREE.Box3().setFromObject(g);
  g.position.y -= caixa.min.y;
  const c = new THREE.Box3().setFromObject(g).getCenter(new THREE.Vector3());
  g.position.x -= c.x; g.position.z -= c.z;
  return g;
}
