#!/usr/bin/env node
// Pixel diff of the gallery between two servers (`mix quacks.visual` starts them
// and writes the job file). For each frame and width: a screenshot of the base
// server and of the head server in the same tab, then a pixel compare in a canvas
// of the same Chrome. Writes <out>/index.html with only the changed shots.
//   node docs/assets/visual.mjs <job.json>
// Job: {frames: [[name, path]], widths, base: {url, ref}, head: {url, ref}, out, cdp, jobs}
// ponytail: no deps, node's built-in fetch and WebSocket.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const job = JSON.parse(readFileSync(process.argv[2], "utf8"));
const CDP = `http://127.0.0.1:${job.cdp}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// The gallery's own frame heights (GalleryLive.height/2): a phone 780, a desktop 800.
const height = (w) => (w < 768 ? 780 : 800);

// No motion: the page's own reduced-motion rules, and every CSS animation and
// transition at 0 s (an animation with fill shows its end, one without its rest).
const STILL = `*, *::before, *::after {
  animation-duration: 0s !important; animation-delay: 0s !important;
  transition-duration: 0s !important; transition-delay: 0s !important;
  caret-color: transparent !important; }
#tidewave-toolbar, iframe[hidden] { display: none !important; }`;

// The same for the animations that JS starts (Element.animate): no duration, no
// delay. A delayed animation with backwards fill holds its first frame for the
// delay, so a shot would catch it before it starts.
const NO_MOTION = `{
  const animate = Element.prototype.animate;
  Element.prototype.animate = function (frames, o) {
    o = typeof o === "object" && o ? { ...o, duration: 0, delay: 0, endDelay: 0 } : { duration: 0 };
    return animate.call(this, frames, o);
  };
  addEventListener("DOMContentLoaded", () => {
    const s = document.createElement("style");
    s.textContent = ${JSON.stringify(STILL)};
    document.head.append(s);
  });
}`;

async function tab() {
  const target = await (await fetch(`${CDP}/json/new?about:blank`, { method: "PUT" })).json();
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r, j) => ((ws.onopen = r), (ws.onerror = j)));
  let next = 0;
  const waiting = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (waiting.has(msg.id)) waiting.get(msg.id)(msg), waiting.delete(msg.id);
  };
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++next;
      waiting.set(id, (msg) => (msg.error ? reject(new Error(`${method}: ${msg.error.message}`)) : resolve(msg.result)));
      ws.send(JSON.stringify({ id, method, params }));
    });
  const js = async (expression) => {
    const r = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result.value;
  };
  const close = async () => (ws.close(), await fetch(`${CDP}/json/close/${target.id}`));
  return { send, js, close };
}

async function shooter() {
  const t = await tab();
  await t.send("Page.enable");
  await t.send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-reduced-motion", value: "reduce" }] });
  await t.send("Page.addScriptToEvaluateOnNewDocument", { source: NO_MOTION });
  let width = 0;
  const capture = async () => {
    const [w, h] = await t.js("[innerWidth, Math.max(document.documentElement.scrollHeight, innerHeight)]");
    const clip = { x: 0, y: 0, width: w, height: h, scale: 1 };
    return (await t.send("Page.captureScreenshot", { format: "png", clip, captureBeyondViewport: true })).data;
  };
  return {
    close: t.close,
    async shot(url, w) {
      if (w !== width) {
        await t.send("Emulation.setDeviceMetricsOverride", { width: w, height: height(w), deviceScaleFactor: 1, mobile: w < 768 });
        width = w;
      }
      const t0 = Date.now();
      await t.send("Page.navigate", { url });
      // The new page is in, its LiveView is connected (a frame is one) and the fonts are in.
      const ready = `location.href === ${JSON.stringify(url)} && document.readyState !== "loading" &&
        (!document.querySelector("[data-phx-main]") || !!document.querySelector("[data-phx-main].phx-connected"))`;
      let connected = false;
      for (let i = 0; i < 300 && !(connected = await t.js(ready).catch(() => false)); i++) await sleep(25);
      await t.js("document.fonts.ready.then(() => true)");
      const t1 = Date.now();
      // Settled: two captures in a row are the same (JS timers, images).
      let shot = await capture();
      for (let i = 0; i < 10; i++) {
        await sleep(200);
        const again = await capture();
        if (again === shot) {
          if (process.env.VISUAL_DEBUG) console.log(url, w, "load", t1 - t0, "settle", Date.now() - t1, "tries", i);
          return { png: shot, settled: connected };
        }
        shot = again;
      }
      return { png: shot, settled: false };
    },
  };
}

// In a blank tab: both PNGs into canvases, count the pixels that differ (a
// channel by more than `tolerance`: text and gradients can be 1 or 2 off from
// one render to the next) and draw
// the overlay (the base in faint grey, the changed pixels red).
const DIFF = `async (a, b, tolerance) => {
  const load = (s) => new Promise((r, j) => { const i = new Image(); i.onload = () => r(i); i.onerror = j; i.src = "data:image/png;base64," + s; });
  const [A, B] = await Promise.all([load(a), load(b)]);
  const w = Math.max(A.width, B.width), h = Math.max(A.height, B.height);
  const pixels = (img) => { const c = new OffscreenCanvas(w, h).getContext("2d"); c.drawImage(img, 0, 0); return c.getImageData(0, 0, w, h).data; };
  const pa = pixels(A), pb = pixels(B);
  const out = new OffscreenCanvas(w, h), ctx = out.getContext("2d"), od = ctx.createImageData(w, h), o = od.data;
  let n = 0;
  for (let i = 0; i < pa.length; i += 4) {
    if (Math.abs(pa[i] - pb[i]) > tolerance || Math.abs(pa[i + 1] - pb[i + 1]) > tolerance ||
        Math.abs(pa[i + 2] - pb[i + 2]) > tolerance || Math.abs(pa[i + 3] - pb[i + 3]) > tolerance) {
      n++; o[i] = 230; o[i + 1] = 0; o[i + 2] = 40; o[i + 3] = 255;
    } else {
      const g = 255 - (255 - (pa[i] * 0.3 + pa[i + 1] * 0.59 + pa[i + 2] * 0.11)) * 0.25;
      o[i] = o[i + 1] = o[i + 2] = g; o[i + 3] = 255;
    }
  }
  ctx.putImageData(od, 0, 0);
  const blob = await out.convertToBlob({ type: "image/png" });
  const url = await new Promise((r) => { const f = new FileReader(); f.onload = () => r(f.result); f.readAsDataURL(blob); });
  return { changed: n, pct: (100 * n) / (w * h), w, h, base: [A.width, A.height], head: [B.width, B.height], png: url.split(",")[1] };
}`;

const items = job.frames.flatMap(([name, path]) => job.widths.map((w) => ({ name, path, w })));
const results = [];
const started = Date.now();
let done = 0;

async function worker() {
  const s = await shooter();
  const d = await tab();
  for (let item; (item = items.shift()); ) {
    const compare = async () => {
      const base = await s.shot(job.base.url + item.path, item.w);
      const head = await s.shot(job.head.url + item.path, item.w);
      const diff = base.png === head.png ? null : await d.js(`(${DIFF})(${JSON.stringify(base.png)}, ${JSON.stringify(head.png)}, ${job.tolerance})`);
      return { base, head, diff: diff?.changed > 0 ? diff : null };
    };
    // A difference must show again: shoot both again, up to 2 times. Under load a
    // page can hold a state for longer than the settle time (a JS timer).
    let { base, head, diff } = await compare();
    let retries = 0;
    while (diff && retries < 2) retries++, ({ base, head, diff } = await compare());
    const r = { ...item, settled: base.settled && head.settled, retries, changed: 0, pct: 0 };
    if (diff) {
      const file = `${item.name.replaceAll("/", "__")}@${item.w}`;
      Object.assign(r, { changed: diff.changed, pct: diff.pct, size: [diff.base, diff.head], file });
      for (const [kind, png] of [["base", base.png], ["head", head.png], ["diff", diff.png]]) {
        writeFileSync(join(job.out, kind, `${file}.png`), Buffer.from(png, "base64"));
      }
    }
    results.push(r);
    if (++done % 50 === 0) console.log(`  ${done} shots compared (${Math.round((Date.now() - started) / 1000)} s)`);
  }
  await s.close();
  await d.close();
}

for (const kind of ["base", "head", "diff"]) mkdirSync(join(job.out, kind), { recursive: true });
await Promise.all(Array.from({ length: job.jobs }, worker));

const seconds = Math.round((Date.now() - started) / 1000);
const changed = results.filter((r) => r.changed > 0).sort((a, b) => b.pct - a.pct || a.name.localeCompare(b.name));
const unsettled = results.filter((r) => !r.settled).map((r) => `${r.name}@${r.w}`);
// Shots that were not the same at first and the same after a retry: a flake.
const flaky = results.filter((r) => r.retries > 0 && r.changed === 0).map((r) => `${r.name}@${r.w}`);
const summary = { base: job.base, head: job.head, shots: results.length, changed: changed.length, seconds, unsettled, flaky };
writeFileSync(join(job.out, "summary.json"), JSON.stringify({ ...summary, results: changed }, null, 2));

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);
const row = (r) => `
<section id="${esc(r.file)}">
  <h2><a href="#${esc(r.file)}">${esc(r.name)}</a> <span>${r.w} px</span> <b>${r.pct.toFixed(r.pct < 0.1 ? 3 : 1)}%</b>
    <small>${r.changed} px${r.size[0].join("x") === r.size[1].join("x") ? "" : `, size ${r.size[0].join("x")} → ${r.size[1].join("x")}`}</small>
    <a class="open" href="${esc(job.head.url + r.path)}">head page</a></h2>
  <div class="row">
    <figure><figcaption>base</figcaption><a href="base/${esc(r.file)}.png"><img loading="lazy" src="base/${esc(r.file)}.png"></a></figure>
    <figure><figcaption>head</figcaption><a href="head/${esc(r.file)}.png"><img loading="lazy" src="head/${esc(r.file)}.png"></a></figure>
    <figure><figcaption>diff</figcaption><a href="diff/${esc(r.file)}.png"><img loading="lazy" src="diff/${esc(r.file)}.png"></a></figure>
  </div>
</section>`;
writeFileSync(
  join(job.out, "index.html"),
  `<!doctype html><meta charset="utf-8"><title>Visual diff ${esc(job.base.ref)} → ${esc(job.head.ref)}</title>
<style>
  body { font: 14px/1.4 system-ui, sans-serif; margin: 16px; background: #f6f5f2; color: #222; }
  h1 { font-size: 18px; } h2 { font-size: 14px; display: flex; gap: 10px; align-items: baseline; flex-wrap: wrap; }
  h2 b { color: #c0142a; } h2 small, h2 span { color: #666; } .open { margin-left: auto; font-weight: normal; }
  section { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 8px 12px; margin: 12px 0; }
  .row { display: flex; gap: 12px; overflow-x: auto; align-items: flex-start; }
  figure { margin: 0; flex: 0 0 auto; } figcaption { font-size: 12px; color: #666; }
  img { display: block; max-width: min(420px, 80vw); border: 1px solid #ccc; }
  ol { columns: 2; font-size: 12px; } code { font-size: 12px; }
</style>
<h1>Visual diff: <code>${esc(job.base.ref)}</code> (${esc(job.base.sha)}) → <code>${esc(job.head.ref)}</code> (${esc(job.head.sha)})</h1>
<p>${changed.length} of ${results.length} shots changed (${job.frames.length} frames × ${job.widths.join("/")} px), ${seconds} s.
Sorted by the part of the shot that changed. Red in the diff: a pixel that is not the same (a channel more than ${job.tolerance} off).
${flaky.length ? `<br>Same only after a retry (flaky, not in the list): ${flaky.map(esc).join(", ")}` : ""}
${unsettled.length ? `<br><b>Not settled</b> (not connected in 7.5 s, or still moving after 2 s): ${unsettled.map(esc).join(", ")}` : ""}</p>
${changed.length ? `<ol>${changed.map((r) => `<li><a href="#${esc(r.file)}">${esc(r.name)} @${r.w}</a> ${r.pct.toFixed(2)}%</li>`).join("")}</ol>` : "<p>No changes.</p>"}
${changed.map(row).join("")}
`,
);
console.log(`${changed.length} of ${results.length} shots changed, ${seconds} s, ${flaky.length} flaky, ${unsettled.length} not settled`);
console.log(join(job.out, "index.html"));
