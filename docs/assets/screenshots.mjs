#!/usr/bin/env node
// Screenshots of the game page on a phone (390x844) and a desktop (1280x800), taken
// through a Chrome with --remote-debugging-port (CDP_PORT, default 9223) against a
// dev server (BASE, default http://localhost:4100). Prints scrollHeight/innerHeight
// for each phone shot: the phone layout must not scroll.
//   node docs/assets/screenshots.mjs
// ponytail: no deps, node's built-in fetch and WebSocket.
import { writeFileSync } from "node:fs";

const PORT = process.env.CDP_PORT || 9223;
const BASE = process.env.BASE || "http://localhost:4100";
const OUT = new URL(".", import.meta.url).pathname;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const target = await (await fetch(`http://localhost:${PORT}/json/new?about:blank`, { method: "PUT" })).json();
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let next = 0;
const waiting = new Map();
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (waiting.has(msg.id)) waiting.get(msg.id)(msg), waiting.delete(msg.id);
};
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = ++next;
    waiting.set(id, (msg) => (msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result)));
    ws.send(JSON.stringify({ id, method, params }));
  });
const js = async (expression) =>
  (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result.value;

const phone = () =>
  send("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
const desktop = () =>
  send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });

const goto = async (url) => {
  await send("Page.navigate", { url });
  await sleep(1500);
};
const click = async (text) => {
  const ok = await js(`(() => {
    const b = [...document.querySelectorAll("button")].find(b => b.textContent.trim().startsWith(${JSON.stringify(text)}) && !b.disabled);
    if (b) b.click();
    return !!b;
  })()`);
  await sleep(500);
  return ok;
};
const results = [];
// The dev-only Tidewave toolbar floats over the action bar; leave it out of the shots.
const hideDevToolbar = () => js(`document.getElementById("tidewave-toolbar")?.remove()`);
const shot = async (name) => {
  await sleep(500); // let a sheet finish sliding in
  await hideDevToolbar();
  const [scroll, inner] = await js("[document.documentElement.scrollHeight, window.innerHeight]");
  results.push(`${name}: scrollHeight ${scroll}, innerHeight ${inner}${scroll <= inner ? "" : "  <-- SCROLLS"}`);
  const { data } = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(`${OUT}${name}.png`, Buffer.from(data, "base64"));
};
// Answer whatever decision dialog is open (first button) until `done()` holds.
const until = async (done, max = 20) => {
  for (let i = 0; i < max && !(await js(done)); i++)
    await js(`document.querySelector("dialog[open] section[aria-label=Actions] button")?.click()`), await sleep(500);
};

await send("Page.enable");
await phone();
await goto(`${BASE}/?seed=10,11,12`);
await click("New solo game");
await sleep(1000);
await until(`!!document.querySelector("button[phx-value-action]") && !document.querySelector("dialog[open]")`);

// Brewing: draw three chips (seed 10,11,12: white 2, 3, 1).
for (let i = 0; i < 3; i++) await click("Draw a chip");
await shot("mobile-brew");

await js(`document.getElementById("sheet-log").showPopover()`);
await shot("mobile-log");
await js(`document.getElementById("sheet-log").hidePopover()`);
await sleep(400);

await click("Stop");
await until(`!!document.querySelector("#decision-buy_chips[open]")`);
await js(`document.querySelector("#shop input:not(:disabled)")?.click()`);
await shot("mobile-shop");

await click("Buy nothing");
await shot("mobile-choice");

await click("End round");
await until(`!!document.querySelector("button[phx-value-action]") && !document.querySelector("dialog[open]")`);
await desktop();
await sleep(500);
for (let i = 0; i < 3; i++) await click("Draw a chip");
await hideDevToolbar();
const { data } = await send("Page.captureScreenshot", { format: "png" });
writeFileSync(`${OUT}desktop.png`, Buffer.from(data, "base64"));
const [scroll, inner] = await js("[document.documentElement.scrollHeight, window.innerHeight]");
results.push(`desktop: scrollHeight ${scroll}, innerHeight ${inner}`);

console.log(results.join("\n"));
ws.close();
await fetch(`http://localhost:${PORT}/json/close/${target.id}`);
