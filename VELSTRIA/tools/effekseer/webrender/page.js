// Velstria の .efk を実際の Effekseer ランタイム（EffekseerForWebGL）で描いてコマを撮るページ（render.mjs が開く）。
// 座標はゲームと同じ: 右手系・Y 上・1 単位 = 1 m。ヒーローは原点で北（-Z）を向き、練習場の人形は北 4 m（FXCapture と同じ置き方）。
// カメラは戦闘のカメラの組（docs/vfx/CAMERA.md）。地面・1 m の格子・照準の輪・ヒーローと人形の代わりの柱は三.js で描き、
// 効果はその深度で隠れる（3D に隠れる層）→ 深度を消して 3D の上の層（top）を描く（アプリの後処理の中の経路と同じ順）。
// bloom を指定すると、アプリの後処理（PostProcess.swift）に近いブルームと色調整を CPU で掛ける（目安。実機の値ではない）。
'use strict';

const CAMERAS = {
  mlbb: { pitch: 42.9, fov: 30.1, distance: 15.9, lead: 0.91 },
  legacy: { pitch: 56, fov: 48, distance: 10, lead: 0 },
  close: { pitch: 42.9, fov: 30.1, distance: 8, lead: 0.5 },
  top: { pitch: 89, fov: 30.1, distance: 18, lead: 0 },
};

let renderer, scene, camera, ctx, spec, frame = 0;
const shots = [];

function initRuntime() {
  return new Promise((resolve, reject) => effekseer.initRuntime('/rt/effekseer.wasm', resolve, () => reject(new Error('wasm'))));
}

function color(hex) { return new THREE.Color(hex); }

function buildScene(s) {
  scene = new THREE.Scene();
  scene.background = color(s.sky);
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(80, 80), new THREE.MeshLambertMaterial({ color: color(s.ground) }));
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);
  if (s.grid) {
    const grid = new THREE.GridHelper(40, 40, 0x8a907c, 0x6c725f);
    grid.position.y = 0.002;
    grid.material.transparent = true;
    grid.material.opacity = 0.35;
    scene.add(grid);
  }
  for (const r of s.rings) {
    const ring = new THREE.Mesh(new THREE.RingGeometry(r - 0.025, r + 0.025, 128),
      new THREE.MeshBasicMaterial({ color: 0x5fd7ff, transparent: true, opacity: 0.8, side: THREE.DoubleSide }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.004;
    scene.add(ring);
  }
  // ヒーロー（ゴルム並みの大柄: 半径 0.55 m・高さ 2.0 m）と人形（半径 0.45 m・高さ 1.7 m）の代わりの柱
  const body = (r, h, c, z) => {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, 24), new THREE.MeshLambertMaterial({ color: c }));
    m.position.set(0, h / 2, z);
    scene.add(m);
  };
  if (s.bodies) {
    body(0.55, 2.0, 0x6a5a4e, 0);
    body(0.45, 1.7, 0x7d7f86, -4);
  }
  const sun = new THREE.DirectionalLight(0xffffff, 0.85);
  sun.position.set(-4, 10, 6);
  scene.add(sun);
  scene.add(new THREE.AmbientLight(0xffffff, 0.55));
}

function buildCamera(s) {
  const c = typeof s.camera === 'string' ? CAMERAS[s.camera] : s.camera;
  camera = new THREE.PerspectiveCamera(c.fov, s.width / s.height, 0.5, 300);
  const p = c.pitch * Math.PI / 180;
  const focus = new THREE.Vector3(s.focus[0], s.focus[1], s.focus[2] - c.lead);
  camera.position.set(focus.x, focus.y + c.distance * Math.sin(p), focus.z + c.distance * Math.cos(p));
  camera.lookAt(focus);
  camera.updateMatrixWorld(true);
  camera.updateProjectionMatrix();
  return c;
}

function loadEffect(name) {
  return new Promise((resolve) => {
    const e = ctx.loadEffect('/fx/' + name + '.efk', 1.0, () => resolve({ e, ok: true }), (m, url) => resolve({ e, ok: false, error: m + ' ' + url }));
  });
}

window.efkSetup = async function (s) {
  spec = s;
  const canvas = document.getElementById('c');
  canvas.width = s.width;
  canvas.height = s.height;
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(s.width, s.height, false);
  buildScene(s);
  const cam = buildCamera(s);
  await initRuntime();
  ctx = effekseer.createContext();
  ctx.init(renderer.getContext(), { instanceMaxCount: 4000, squareMaxCount: 10000 });
  ctx.setRestorationOfStatesFlag(true);
  const loaded = {};
  for (const fx of s.fx) {
    if (!loaded[fx.name]) loaded[fx.name] = await loadEffect(fx.name);
    fx.effect = loaded[fx.name].e;
  }
  frame = 0;
  shots.length = 0;
  playDue();
  const errors = Object.entries(loaded).filter(([, v]) => !v.ok).map(([k, v]) => k + ': ' + v.error);
  return { camera: cam, errors };
};

function playDue() {
  for (const fx of spec.fx) {
    if (fx.handle || frame < fx.delay) continue;
    const h = ctx.play(fx.effect, fx.pos[0], fx.pos[1], fx.pos[2]);
    if (spec.seed != null && h.setRandomSeed) h.setRandomSeed(spec.seed);
    h.setRotation(0, fx.yaw * Math.PI / 180, 0);
    h.setScale(fx.scale, fx.scale, fx.scale);
    if (fx.speed !== 1 && h.setSpeed) h.setSpeed(fx.speed);
    fx.handle = h;
  }
}

function draw() {
  renderer.render(scene, camera);
  const gl = renderer.getContext();
  ctx.setProjectionMatrix(camera.projectionMatrix.elements);
  ctx.setCameraMatrix(camera.matrixWorldInverse.elements);
  // 3D に隠れる層 → 深度を消す → 3D の上の層（アプリの後処理の中と同じ順）
  ctx.beginDraw();
  for (const fx of spec.fx) if (fx.handle && !fx.top) ctx.drawHandle(fx.handle);
  ctx.endDraw();
  if (spec.fx.some((fx) => fx.handle && fx.top)) {
    gl.depthMask(true);
    gl.clear(gl.DEPTH_BUFFER_BIT);
    ctx.beginDraw();
    for (const fx of spec.fx) if (fx.handle && fx.top) ctx.drawHandle(fx.handle);
    ctx.endDraw();
  }
}

// ---- ブルーム（アプリの PostProcess.swift の近似: 輝度抽出 0.6・柔らかさ 0.3・彩度の重み → 1/2〜1/32 → 拡大で混ぜる 0.75 → スクリーン合成）

function bloomify(img, intensity) {
  const W = img.width, H = img.height, d = img.data;
  let w = W >> 1, h = H >> 1;
  let level = new Float32Array(w * h * 3);
  const th = 0.6, knee = 0.3;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let r = 0, g = 0, b = 0;
      for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
        const i = ((y * 2 + dy) * W + x * 2 + dx) * 4;
        r += d[i]; g += d[i + 1]; b += d[i + 2];
      }
      r /= 1020; g /= 1020; b /= 1020;
      const br = Math.max(r, g, b), mn = Math.min(r, g, b);
      let soft = Math.min(Math.max(br - th + knee, 0), 2 * knee);
      soft = soft * soft / (4 * knee + 1e-5);
      const contrib = Math.max(soft, br - th) / Math.max(br, 1e-4);
      const sat = (br - mn) / Math.max(br, 1e-4);
      const t = Math.min(Math.max((sat - 0.18) / 0.37, 0), 1);
      const wgt = t * t * (3 - 2 * t);
      const k = (y * w + x) * 3;
      level[k] = r * contrib * wgt; level[k + 1] = g * contrib * wgt; level[k + 2] = b * contrib * wgt;
    }
  }
  const levels = [{ a: level, w, h }];
  for (let n = 1; n < 5; n++) {
    const p = levels[n - 1], nw = Math.max(1, p.w >> 1), nh = Math.max(1, p.h >> 1), a = new Float32Array(nw * nh * 3);
    for (let y = 0; y < nh; y++) for (let x = 0; x < nw; x++) for (let c = 0; c < 3; c++) {
      let s = 0;
      for (let dy = -1; dy <= 2; dy++) for (let dx = -1; dx <= 2; dx++) {
        const sx = Math.min(p.w - 1, Math.max(0, x * 2 + dx)), sy = Math.min(p.h - 1, Math.max(0, y * 2 + dy));
        s += p.a[(sy * p.w + sx) * 3 + c];
      }
      a[(y * nw + x) * 3 + c] = s / 16;
    }
    levels.push({ a, w: nw, h: nh });
  }
  const sample = (L, u, v, c) => {
    const x = Math.min(L.w - 1, Math.max(0, u * L.w - 0.5)), y = Math.min(L.h - 1, Math.max(0, v * L.h - 0.5));
    const x0 = Math.floor(x), y0 = Math.floor(y), x1 = Math.min(L.w - 1, x0 + 1), y1 = Math.min(L.h - 1, y0 + 1);
    const fx = x - x0, fy = y - y0, A = L.a;
    return (A[(y0 * L.w + x0) * 3 + c] * (1 - fx) + A[(y0 * L.w + x1) * 3 + c] * fx) * (1 - fy)
      + (A[(y1 * L.w + x0) * 3 + c] * (1 - fx) + A[(y1 * L.w + x1) * 3 + c] * fx) * fy;
  };
  let up = levels[levels.length - 1];
  for (let n = levels.length - 2; n >= 0; n--) {
    const L = levels[n], a = new Float32Array(L.w * L.h * 3);
    for (let y = 0; y < L.h; y++) for (let x = 0; x < L.w; x++) for (let c = 0; c < 3; c++) {
      const u = (x + 0.5) / L.w, v = (y + 0.5) / L.h;
      a[(y * L.w + x) * 3 + c] = L.a[(y * L.w + x) * 3 + c] * 0.25 + sample(up, u, v, c) * 0.75;
    }
    up = { a, w: L.w, h: L.h };
  }
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4, u = (x + 0.5) / W, v = (y + 0.5) / H;
    let rgb = [d[i] / 255, d[i + 1] / 255, d[i + 2] / 255];
    for (let c = 0; c < 3; c++) {
      const b = Math.min(sample(up, u, v, c) * intensity, 1);
      rgb[c] = 1 - (1 - rgb[c]) * (1 - b);
      rgb[c] = (rgb[c] - 0.5) * 1.06 + 0.5;
    }
    const lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
    for (let c = 0; c < 3; c++) d[i + c] = Math.max(0, Math.min(255, Math.round((lum + (rgb[c] - lum) * 1.08) * 255)));
  }
  return img;
}

function grab() {
  const c = document.getElementById('c');
  const out = document.createElement('canvas');
  const [cx, cy, cw, ch] = spec.crop || [0, 0, c.width, c.height];
  out.width = cw;
  out.height = ch;
  const g = out.getContext('2d');
  g.drawImage(c, cx, cy, cw, ch, 0, 0, cw, ch);
  if (spec.bloom > 0) g.putImageData(bloomify(g.getImageData(0, 0, cw, ch), spec.bloom), 0, 0);
  return out;
}

/// n フレーム（1/60 秒）進める。
window.efkStep = function (n) {
  for (let i = 0; i < n; i++) {
    ctx.update(1);
    frame += 1;
    playDue();
  }
  return frame;
};

/// 今のフレームを描いて PNG（data URL）を返す。sheet に残す。
window.efkShot = function () {
  draw();
  const c = grab();
  shots.push({ frame, canvas: c });
  return c.toDataURL('image/png');
};

/// 撮ったコマを 1 枚に並べる（左上にフレームと秒）。
window.efkSheet = function (cols, scale) {
  if (!shots.length) return null;
  const w = Math.round(shots[0].canvas.width * scale), h = Math.round(shots[0].canvas.height * scale);
  const rows = Math.ceil(shots.length / cols);
  const out = document.createElement('canvas');
  out.width = w * cols;
  out.height = h * rows;
  const g = out.getContext('2d');
  g.fillStyle = '#000';
  g.fillRect(0, 0, out.width, out.height);
  g.font = 'bold 14px sans-serif';
  shots.forEach((s, k) => {
    const x = (k % cols) * w, y = Math.floor(k / cols) * h;
    g.drawImage(s.canvas, x, y, w, h);
    const label = 'f' + s.frame + ' ' + (s.frame / 60).toFixed(2) + 's';
    g.fillStyle = 'rgba(0,0,0,0.6)';
    g.fillRect(x, y, g.measureText(label).width + 10, 20);
    g.fillStyle = '#fff';
    g.fillText(label, x + 5, y + 15);
  });
  return out.toDataURL('image/png');
};

window.__efkPageReady = true;
