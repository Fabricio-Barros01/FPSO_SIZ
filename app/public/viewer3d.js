// Vendorizado do handoff de design — References/FPSO SIZ UI mockups/viewer3d.js
//
// CÓPIA. A origem é o artboard do Claude Design; alterar só esta cópia faz o app
// divergir do handoff sem nada denunciar.
//
// `import ... from 'three'` resolve pelo mapa de importação de `casca.html`, que aponta
// para `/vendor/` — local, porque o programa empacotado abre sem internet.
// <fpso-3d> — visor 3D embutido, para a área principal da figura.
// Substitui a elevação SVG (app/src/desenho/vaso.jl) mantendo o mesmo papel: a figura
// grande da coluna do meio, que responde ao cursor de diâmetro / DN.
//
// Atributos: modelo="separador|bomba", d, lss, leff, beta, nivel, dn, lod, fases.
// Reage a mudança de atributo (o DC os reescreve a cada render).
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { buildSeparador } from './models/separador.js';
import { buildBomba } from './models/bomba.js';
import { buildTrocador } from './models/trocador.js';

class Fpso3D extends HTMLElement {
  static observedAttributes = ['modelo', 'd', 'lss', 'leff', 'beta', 'nivel', 'dn', 'lod',
    'fases', 'n-tubos', 'passes', 'l'];

  connectedCallback() {
    if (this._on) return;
    this._on = true;
    this.style.display = 'block';
    this.style.position = 'relative';

    const cena = new THREE.Scene();
    const r = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    r.setPixelRatio(Math.min(devicePixelRatio, 2));
    r.shadowMap.enabled = true;
    r.shadowMap.type = THREE.PCFSoftShadowMap;
    Object.assign(r.domElement.style, { width: '100%', height: '100%', display: 'block' });
    this.appendChild(r.domElement);

    cena.add(new THREE.HemisphereLight(0xffffff, 0x93a2b3, 1.05));
    const key = new THREE.DirectionalLight(0xffffff, 1.45);
    key.position.set(6, 9, 7); key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024); key.shadow.bias = -0.0005;
    cena.add(key);
    const fill = new THREE.DirectionalLight(0xffffff, 0.45);
    fill.position.set(-7, 3, -5); cena.add(fill);

    const chao = new THREE.Mesh(
      new THREE.PlaneGeometry(400, 400),
      new THREE.ShadowMaterial({ opacity: 0.16 }));
    chao.rotation.x = -Math.PI / 2; chao.receiveShadow = true;
    cena.add(chao);

    const cam = new THREE.PerspectiveCamera(34, 1, 0.05, 900);
    const ctr = new OrbitControls(cam, r.domElement);
    ctr.enableDamping = true; ctr.dampingFactor = 0.08;
    ctr.minPolarAngle = 0.25; ctr.maxPolarAngle = Math.PI / 2 - 0.02;
    ctr.enablePan = false;

    Object.assign(this, { _r: r, _cena: cena, _cam: cam, _ctr: ctr, _key: key });

    const ro = new ResizeObserver(() => this._medir());
    ro.observe(this);
    this._ro = ro;

    const laco = () => {
      if (!this.isConnected) return;
      this._raf = requestAnimationFrame(laco);
      ctr.update();
      r.render(cena, cam);
    };
    this._medir();
    this._construir(true);
    laco();
  }

  disconnectedCallback() {
    cancelAnimationFrame(this._raf);
    this._ro?.disconnect();
    this._r?.dispose();
    this._on = false;
  }

  attributeChangedCallback() { if (this._on) this._construir(false); }

  _medir() {
    const w = this.clientWidth || 640, h = this.clientHeight || 360;
    this._r.setSize(w, h, false);
    this._cam.aspect = w / h;
    this._cam.updateProjectionMatrix();
  }

  _num(n, pad) { const v = parseFloat(this.getAttribute(n)); return Number.isFinite(v) ? v : pad; }

  _construir(primeiro) {
    const lod = this.getAttribute('lod') || 'detalhado';
    const modelo = this.getAttribute('modelo') || 'separador';
    let obj;
    if (modelo === 'bomba') {
      obj = buildBomba({ dn: this._num('dn', 250), lod });
    } else if (modelo === 'trocador') {
      obj = buildTrocador({
        nTubos: this._num('n-tubos', 120), passes: this._num('passes', 2),
        l: this._num('l', 6), lod });
    } else {
      obj = buildSeparador({
        tipo: modelo,
        d: this._num('d', 5.65), lss: this._num('lss', 21.78), leff: this._num('leff', 16.34),
        beta: this._num('beta', 0.03), nivel: this._num('nivel', 0.5), lod,
        fases: this.getAttribute('fases') !== 'false',
      });
    }

    if (this._obj) {
      this._cena.remove(this._obj);
      this._obj.traverse((n) => {
        if (n.isMesh) { n.geometry.dispose(); n.material.dispose(); }
      });
    }    this._obj = obj;
    this._cena.add(obj);

    const caixa = new THREE.Box3().setFromObject(obj);
    const centro = caixa.getCenter(new THREE.Vector3());
    const tam = caixa.getSize(new THREE.Vector3());
    const raio = Math.max(tam.x, tam.y, tam.z);
    this._key.shadow.camera.left = -raio; this._key.shadow.camera.right = raio;
    this._key.shadow.camera.top = raio; this._key.shadow.camera.bottom = -raio;
    this._key.shadow.camera.far = raio * 6;
    this._key.position.set(centro.x + raio * 0.6, raio * 1.6, centro.z + raio * 0.7);
    this._key.shadow.camera.updateProjectionMatrix();

    this._ctr.target.copy(centro);
    if (primeiro) {
      const dist = raio * 1.05;
      this._cam.position.set(centro.x + dist * 0.72, centro.y + dist * 0.42, centro.z + dist * 0.78);
      this._ctr.minDistance = raio * 0.45;
      this._ctr.maxDistance = raio * 3.2;
    }
    this._cam.near = Math.max(raio / 400, 0.02);
    this._cam.far = raio * 40;
    this._cam.updateProjectionMatrix();
    this._ctr.update();
  }
}

if (!customElements.get('fpso-3d')) customElements.define('fpso-3d', Fpso3D);
