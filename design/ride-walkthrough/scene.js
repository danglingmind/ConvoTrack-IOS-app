// scene.js — the whole timeline of index.html. window.renderAt(t) sets every element from t alone.
//
// Camera: ONE path through the whole video (no per-shot cameras, so nothing jumps at a screen
// change), through keyframes [beat, fx, fy, zoom] with a monotone cubic spline per channel:
// continuous velocity, no overshoot. Zoom is interpolated in log space so it feels even.
// Screens: each change is a real-looking navigation — push (new screen from the right, old one
// slides left and dims), sheet (rises from the bottom) or fade (state change in place).

// ---- beat grid: 96 BPM, 32 beats = 20.000 s ----
const B = 60 / 96;
const SW = 587.5, SH = 1277.3, INSET = 26.3;          // screen size and its offset in the phone

// Screens in order: [key, beat the change starts, transition, seconds]. A change starts a moment
// after the tap that causes it, as in the app.
const LAG = 0.12;
const SCREENS = [
  ['home',    0,             null,    0],
  ['planner', 4 + LAG / B,   'push',  0.62],
  ['typing',  6 + LAG / B,   'fade',  0.30],
  ['suggest', 7.5,           'fade',  0.25],
  ['route',   9 + LAG / B,   'fade',  0.45],
  ['lobby',   17 + LAG / B,  'push',  0.62],
  ['prenav',  21 + LAG / B,  'sheet', 0.62],
  ['nav',     24 + LAG / B,  'fade',  0.28],
];

// Taps: [beat, screen fx, fy] — measured on the captures.
const TAPS = [
  [4,  .268, .3695],   // Create ride (home)
  [6,  .435, .105],    // search field
  [9,  .267, .1835],   // "Nandi Hills" suggestion
  [17, .500, .9065],   // Create ride (route)
  [21, .500, .859],    // Start ride (lobby)
  [24, .500, .8785],   // Start navigation
];

// Camera keyframes: [beat, fx, fy, zoom]. fx/fy = point of the screen held at frame centre.
const CAM = [
  [0,    .50, .46, 0.94],
  [3.6,  .36, .37, 1.40],    // settle on Create ride before the tap
  [4.9,  .44, .26, 1.30],    // ride the push into the planner
  [5.7,  .50, .14, 1.42],    // search field
  [8.4,  .50, .17, 1.47],    // typing → suggestion
  [9.9,  .50, .50, 1.00],    // the route appears: whole phone
  [11.4, .45, .16, 1.52],    // Cubbon Park → Nandi Hills
  [12.4, .45, .17, 1.55],
  [13.4, .44, .47, 1.22],    // ease back while travelling down
  [14.4, .43, .78, 1.52],    // 1h 47m (56.7 km)
  [15.5, .43, .79, 1.54],
  [16.5, .50, .87, 1.38],    // Create ride button
  [17.9, .50, .42, 1.12],    // lobby arrives
  [19.2, .50, .62, 1.40],    // ride details
  [20.5, .50, .70, 1.38],
  [21.9, .50, .56, 1.00],    // sheet rises: route preview
  [23.3, .50, .82, 1.42],    // destination card + Start navigation
  [24.3, .50, .50, 1.10],    // ease back while the turn card arrives
  [25.7, .50, .15, 1.52],    // turn card
  [27.0, .50, .16, 1.55],
  [28.2, .50, .48, 0.98],    // pull back
  [29.4, .50, .48, 0.78],    // keep receding under the end card
];
const END_FROM = 28.0;       // end card fades in from here

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const smooth = x => x * x * (3 - 2 * x);
const out = x => 1 - Math.pow(1 - x, 3);
// iOS-like navigation curve: quick start, long soft landing, no bounce.
const navEase = x => 1 - Math.pow(1 - smooth(clamp(x)), 3);

// Where the phone body may sit: when it is taller than the frame, never leave an empty band
// above or below it. Applied to the KEYFRAMES (as an effective focus point), not per frame,
// so the spline stays smooth.
function effectiveFy(fy, z) {
  const py = INSET + fy * SH, ph = 1330 * z;
  let ty = 960 - py * z;
  if (ph > 1520) ty = Math.min(200, Math.max(1720 - ph, ty));
  return ((960 - ty) / z - INSET) / SH;
}

// Monotone cubic (Fritsch–Carlson) through (xs, ys).
function monotone(xs, ys) {
  const n = xs.length, d = [], m = new Array(n);
  for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
  m[0] = 0; m[n - 1] = 0;                                     // start and end at rest
  for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  for (let i = 0; i < n - 1; i++) {
    if (d[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
    const a = m[i] / d[i], b = m[i + 1] / d[i], h = a * a + b * b;
    if (h > 9) { const k = 3 / Math.sqrt(h); m[i] = k * a * d[i]; m[i + 1] = k * b * d[i]; }
  }
  return x => {
    if (x <= xs[0]) return ys[0];
    if (x >= xs[n - 1]) return ys[n - 1];
    let i = 0; while (x > xs[i + 1]) i++;
    const h = xs[i + 1] - xs[i], s = (x - xs[i]) / h, s2 = s * s, s3 = s2 * s;
    return (2 * s3 - 3 * s2 + 1) * ys[i] + (s3 - 2 * s2 + s) * h * m[i] + (-2 * s3 + 3 * s2) * ys[i + 1] + (s3 - s2) * h * m[i + 1];
  };
}
const camX = monotone(CAM.map(k => k[0]), CAM.map(k => k[1]));
const camY = monotone(CAM.map(k => k[0]), CAM.map(k => effectiveFy(k[2], k[3])));
const camZ = monotone(CAM.map(k => k[0]), CAM.map(k => Math.log(k[3])));

const imgs = Object.fromEntries([...document.querySelectorAll('#screen img')].map(im => [im.dataset.k, im]));
const rig = document.getElementById('rig'), endEl = document.getElementById('end');
const tap = document.getElementById('tap'), dot = document.getElementById('dot'), ripple = document.getElementById('ripple');

function renderScreens(t) {
  for (const im of Object.values(imgs)) Object.assign(im.style, { display: 'none', transform: '', opacity: 1, filter: '', boxShadow: '', zIndex: 0 });
  let i = 0;
  while (i + 1 < SCREENS.length && t >= SCREENS[i + 1][1] * B) i++;
  const [key, start, kind, dur] = SCREENS[i];
  const cur = imgs[key];
  cur.style.display = 'block'; cur.style.zIndex = 2;
  const p = kind ? clamp((t - start * B) / dur) : 1;
  if (p >= 1 || i === 0) return;
  const prev = imgs[SCREENS[i - 1][0]], e = navEase(p);
  prev.style.display = 'block'; prev.style.zIndex = 1;
  if (kind === 'push') {
    cur.style.transform = `translateX(${100 * (1 - e)}%)`;
    cur.style.boxShadow = '-24px 0 48px rgba(0,0,0,0.55)';
    prev.style.transform = `translateX(${-30 * e}%)`;
    prev.style.filter = `brightness(${1 - 0.45 * e})`;
  } else if (kind === 'sheet') {
    cur.style.transform = `translateY(${100 * (1 - e)}%)`;
    cur.style.boxShadow = '0 -24px 48px rgba(0,0,0,0.55)';
    prev.style.transform = `scale(${1 - 0.06 * e})`;
    prev.style.filter = `brightness(${1 - 0.5 * e})`;
  } else {
    cur.style.opacity = smooth(p);
  }
}

function renderTap(t) {
  // Finger lands over 0.3 s before the beat, presses on the beat, lifts with one ripple (0.55 s).
  const tp = TAPS.find(([b]) => t > b * B - 0.3 && t < b * B + 0.55);
  tap.style.display = tp ? 'block' : 'none';
  if (!tp) return;
  const dt = t - tp[0] * B;
  tap.style.left = (tp[1] * SW) + 'px'; tap.style.top = (tp[2] * SH) + 'px';
  const inK = out(clamp((dt + 0.3) / 0.3)), upK = clamp(dt / 0.55);
  const d = dt < 0 ? 96 - 28 * inK : 68 - 10 * Math.sin(Math.PI * clamp(dt / 0.16));
  Object.assign(dot.style, { width: d + 'px', height: d + 'px', opacity: dt < 0 ? inK : 1 - smooth(clamp((dt - 0.15) / 0.4)) });
  const r = dt < 0 ? 0 : 68 + 110 * out(upK);
  Object.assign(ripple.style, { width: r + 'px', height: r + 'px', opacity: dt < 0 ? 0 : 0.9 * (1 - upK) });
}

function renderEnd(t) {
  const u = t - END_FROM * B;                       // seconds into the end card
  endEl.style.display = u > 0 ? 'block' : 'none';
  // The phone recedes and fades while the card comes up over it.
  rig.style.opacity = 1 - smooth(clamp(u / 0.6));
  if (u <= 0) return;
  const a = out(clamp((u - 0.45) / 0.5));      // logo only once the phone has mostly gone
  const logo = document.getElementById('logo');
  logo.style.opacity = a;
  logo.style.transform = `scale(${0.9 + 0.1 * a + 0.03 * clamp(u / 2.5)})`;
  if (u < 0.45) logo.style.opacity = 0;
  const w = out(clamp((u - 0.65) / 0.5)), g = out(clamp((u - 0.85) / 0.5));
  Object.assign(document.getElementById('word').style, { opacity: w, transform: `translateY(${22 * (1 - w)}px)` });
  Object.assign(document.getElementById('tag').style, { opacity: g, transform: `translateY(${22 * (1 - g)}px)` });
}

window.renderAt = function (t) {
  const beat = t / B;
  const fx = camX(beat), fy = camY(beat), z = Math.exp(camZ(beat));
  const px = INSET + fx * SW, py = INSET + fy * SH;
  rig.style.transform = `translate(${540 - px * z}px, ${960 - py * z}px) scale(${z})`;
  renderScreens(t);
  renderTap(t);
  renderEnd(t);
};

window.DURATION = 32 * B;
// Resolves once every screenshot is decoded, so a renderer never captures a blank screen.
window.ready = Promise.all([...document.images].map(im => im.decode().catch(() => {})));
const q = new URLSearchParams(location.search);
window.ready.then(() => window.renderAt(parseFloat(q.get('t') || '0')));
