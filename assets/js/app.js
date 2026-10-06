// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/quacks"
import topbar from "../vendor/topbar"

// "Report a problem" (bug_report_components.ex): keep the last 10 console errors,
// and on submit put them with the browser details in the form's hidden field.
const recentErrors = []
const keepError = text => { recentErrors.push(String(text).slice(0, 300)); recentErrors.length > 10 && recentErrors.shift() }
window.addEventListener("error", e => keepError(`${e.message} (${e.filename}:${e.lineno})`))
window.addEventListener("unhandledrejection", e => keepError(`Unhandled rejection: ${e.reason}`))
const consoleError = console.error
console.error = (...args) => { keepError(args.map(String).join(" ")); consoleError.apply(console, args) }
document.addEventListener("submit", e => {
  const field = e.target.matches?.("[data-bug-report]") && e.target.querySelector("[data-role=browser-details]")
  if (field) field.value = JSON.stringify({ua: navigator.userAgent, viewport: `${innerWidth}x${innerHeight}`, online: navigator.onLine, errors: recentErrors})
}, true)

// The configure screen remembers the host's last settings (see `ConfigMemory` in
// game_live.ex): the server pushes each change; a fresh screen sends them back once.
const ConfigMemory = {
  mounted() {
    this.handleEvent("save_config", config => {
      try { localStorage.setItem("quacks:config", JSON.stringify(config)) } catch (_e) {}
    })
    try {
      const saved = JSON.parse(localStorage.getItem("quacks:config"))
      if (saved && typeof saved === "object" && this.el.dataset.fresh !== undefined) this.pushEvent("load_config", saved)
    } catch (_e) {}
  }
}

// Your name on the configure screen: kept in this browser, and filled in on a new
// table where your seat still has the default name ("Player N").
const NameMemory = {
  mounted() {
    this.el.addEventListener("input", () => {
      try { localStorage.setItem("quacks:name", this.el.value.trim()) } catch (_e) {}
    })
    try {
      const saved = localStorage.getItem("quacks:name")
      if (saved && this.el.value === "") { this.el.value = saved; this.pushEvent("rename", {name: saved}) }
    } catch (_e) {}
  }
}

// The menu's reveal settings (round 14, `reveal_settings/1`): Step or Auto, and
// the speed, kept in this browser like `quacks:config`. On mount and on every
// change the hook sends them to the server, with reduced motion (Step only then).
// The speed also sets `--beat-ms` on <html>, so the pot's CSS beats keep in step.
const beatMs = {normal: 450, slow: 720, slower: 1125}
const loadReveal = () => {
  try { return JSON.parse(localStorage.getItem("quacks:reveal")) || {} } catch (_e) { return {} }
}
const setBeat = speed => document.documentElement.style.setProperty("--beat-ms", beatMs[speed] || beatMs.normal)
setBeat(loadReveal().speed)
const RevealSettings = {
  mounted() {
    const send = ({mode, speed}) => {
      setBeat(speed)
      this.pushEvent("reveal_settings", {mode, speed, reduced: reduced()})
    }
    this.el.addEventListener("change", () => {
      const form = new FormData(this.el)
      const settings = {mode: form.get("mode") || "step", speed: form.get("speed") || "normal"}
      try { localStorage.setItem("quacks:reveal", JSON.stringify(settings)) } catch (_e) {}
      setBeat(settings.speed)
    })
    const saved = loadReveal()
    send({mode: saved.mode || "step", speed: saved.speed || "normal"})
  }
}

// The menu's "App" line (round 14): which install rule fails on a phone that shows
// no Install button. The worker, the display mode and whether Chrome fired
// `beforeinstallprompt` on this page (`installFired`, set below).
let installFired = false
const AppStatus = {
  mounted() {
    this.show = () => this.render()
    this.show()
    window.addEventListener("quacks:install", this.show)
    navigator.serviceWorker?.addEventListener("controllerchange", this.show)
    document.getElementById("sheet-menu")?.addEventListener("toggle", this.show)
  },
  destroyed() { window.removeEventListener("quacks:install", this.show) },
  async render() {
    const reg = await navigator.serviceWorker?.getRegistration().catch(() => null)
    const worker = reg?.active ? "active" : (reg?.installing || reg?.waiting) ? "installing" : "none"
    const display = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true ? "standalone" : "browser"
    const prompt = installFired || document.documentElement.dataset.install === "ready" ? "fired" : "not fired"
    this.el.textContent = `App: worker: ${worker} · display: ${display} · install prompt: ${prompt}`
  },
}

// The large pot's motion (docs/research/animations.md §3 B3, round 10). Every patch
// already shows the final pot; this only plays WAAPI `transform`/`opacity` on top, so
// it never holds up a tap. A new chip drops in on its own space (from 1.3× and a
// little above, then the pop); a chip that leaves flies as a ghost to the flask (or
// the bag); at a new round the old chips fade and the new rats slide in from the
// droplet. The scoring sequence's rubies fly to the ruby counter on their beats.
// Reduced motion: fades only, no flights.
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const easing = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()
const at = (p, o, s = 1) => `translate(${p.x - o.x}px, ${p.y - o.y}px) scale(${s})`

const PotMotion = {
  // Running animations go on through later patches (a bot's draw is a patch too):
  // WAAPI writes no attributes, and each chip keeps its node.
  mounted() {
    this.snapshot()
    this.flown = new Set()
    this.flights()
  },
  beforeUpdate() { this.snapshot() },
  updated() {
    const chips = [...this.el.querySelectorAll("[data-role=pot-chip]")]
    const added = chips.filter(c => !this.chips.has(c.id))
    const gone = [...this.chips.values()].filter(c => !c.isConnected)
    const flask = this.full && !this.el.querySelector("[data-role=flask-brew]")
    if (this.el.dataset.round !== this.round) {
      gone.sort((a, b) => a.dataset.order - b.dataset.order).forEach((c, i) => this.ghost(c, null, i * 20))
      this.ratsIn()
    }
    else if (gone.length === 1 && added.length === 0)
      this.ghost(gone[0], this.centre(flask ? this.el.querySelector("[data-role=flask]") : this.bag()))
    else if (added.length <= 2) added.forEach(c => this.land(c))
    this.snapshot()
    this.flights()
  },
  // The scoring sequence: each ruby the round paid waits on its piece (the droplet,
  // a chip, the scoring space) until its line's beat, lifts 12 px, then flies on an
  // arc to the ruby counter and fades there, 600 ms. The same beat formula as the
  // CSS (`--beat-lead`, `--beat-step`, both from `--beat-ms`). Each flight plays once.
  flights() {
    const counter = document.getElementById("stat-rubies")
    const step = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--beat-ms")) || 450
    const ms = name => name === "--beat-step" ? step : step * 2 / 3
    this.el.querySelectorAll("[data-role=ruby-flight]").forEach(f => {
      if (this.flown.has(f.id) || reduced() || !counter) return
      this.flown.add(f.id)
      const p = {x: +f.dataset.x, y: +f.dataset.y}, t = this.centre(counter)
      const dx = t.x - p.x, dy = t.y - p.y
      const delay = ms("--beat-lead") + f.dataset.beat * ms("--beat-step") + +f.dataset.wait + f.dataset.n * 90
      f.firstElementChild.animate([
        {transform: "translate(0px, 0px) scale(1)", opacity: 0, easing: easing("--ease-out")},
        {transform: "translate(0px, -12px) scale(1.3)", opacity: 1, offset: 0.23, easing: easing("--ease-in-out")},
        {transform: `translate(${dx * 0.45}px, ${dy * 0.45 - 40}px) scale(1.05)`, opacity: 1, offset: 0.6},
        {transform: `translate(${dx}px, ${dy}px) scale(0.7)`, opacity: 1, offset: 0.92},
        {transform: `translate(${dx}px, ${dy}px) scale(0.7)`, opacity: 0},
      ], {duration: 600, delay})
    })
  },
  // A new round: the rats for it slide in from the droplet to their spaces, one
  // after the other (240 ms, 60 ms stagger).
  ratsIn() {
    if (reduced()) return
    const drop = this.el.querySelector("[data-role=droplet]")
    if (!drop) return
    const from = this.pos(drop.dataset.index)
    this.el.querySelectorAll("[data-role=rat]").forEach((rat, i) => {
      if (!this.el.querySelector(`[data-space="${rat.dataset.index}"]`)) return
      const to = this.pos(rat.dataset.index)
      rat.animate([{translate: `${from.x}px ${from.y}px`, opacity: 0}, {translate: `${to.x}px ${to.y}px`, opacity: 1}],
        {duration: 240, delay: 200 + i * 60, fill: "backwards", easing: easing("--ease-out")})
    })
  },
  snapshot() {
    this.chips = new Map([...this.el.querySelectorAll("[data-role=pot-chip]")].map(c => [c.id, c]))
    this.full = !!this.el.querySelector("[data-role=flask-brew]")
    this.round = this.el.dataset.round
  },
  pos(i) { const g = this.el.querySelector(`[data-space="${i}"]`).dataset; return {x: +g.x, y: +g.y} },
  bag() { return document.querySelector("[data-role=bag-button]") },
  // An element's centre in the pot's SVG units; the lower right corner without one.
  centre(el) {
    const r = el?.getBoundingClientRect()
    if (!r?.width) return {x: 230, y: 230}
    return new DOMPoint(r.x + r.width / 2, r.y + r.height / 2).matrixTransform(this.el.getScreenCTM().inverse())
  },
  // Drop-in on the chip's own space: it falls a little and shrinks to size as it
  // fades in, then lands with the spring pop. 350 ms; replaces the CSS `chip-land`.
  land(chip) {
    if (reduced()) return
    chip.getAnimations().forEach(a => a.cancel())
    chip.animate([
      {transform: "translate(0px, -12px) scale(1.3)", opacity: 0, easing: easing("--ease-out")},
      {transform: "translate(0px, 0px) scale(1)", opacity: 1, offset: 0.55, easing: easing("--ease-out")},
      {transform: "translate(0px, 0px) scale(1.06)", opacity: 1, offset: 0.75, easing: easing("--ease-spring")},
      {transform: "translate(0px, 0px) scale(1)", opacity: 1},
    ], {duration: 350})
  },
  // A chip that left, put back where it was (out of LiveView's way) to fly to
  // `target`, or, without one, to fade out after `delay` ms.
  ghost(el, target, delay = 0) {
    const fx = this.el.querySelector("[data-role=pot-fx]"), p = this.pos(el.dataset.index)
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("transform", `translate(${p.x} ${p.y})`)
    el.removeAttribute("id")
    g.append(el)
    fx.append(g)
    el.getAnimations().forEach(a => a.cancel())
    const fade = reduced() || !target
    const frames = fade
      ? [{opacity: 1}, {opacity: 0}]
      : [{transform: at(p, p), opacity: 1}, {transform: at(target, p, 0.6), opacity: 1, offset: 0.75},
         {transform: at(target, p, 0.5), opacity: 0}]
    el.animate(frames, {duration: fade ? 180 : 260, delay, fill: "backwards", easing: easing("--ease-out")})
      .finished.catch(() => {}).finally(() => g.remove())
  },
}

let vtNext = false, vtQueue = null
window.addEventListener("phx:quacks:vt", () => { vtNext = true })
const queue = p => { vtQueue = p; p.then(() => { if (vtQueue === p) vtQueue = null }) }

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AppStatus, ConfigMemory, NameMemory, PotMotion, RevealSettings},
  // Hotkeys (`hotkey` in game_live.ex): each keydown also says whether the focus
  // is in a field, on a control that Space/Enter already press, or whether a modal
  // dialog is open. The server decides from that; no key logic here.
  metadata: {
    keydown: e => ({
      typing: !!e.target.closest?.("input, textarea, select, [contenteditable]"),
      control: !!e.target.closest?.("button, a, summary, label"),
      modal: !!document.querySelector("dialog:modal"),
    }),
  },
  // Opt-in view transitions (animations.md §1.4): the server marks the one patch
  // that changes the round (`quacks:vt`, dispatched before it); every other patch,
  // bots' included, goes straight in, except while a transition's patch waits for
  // its snapshot: then patches queue behind it, so they stay in order.
  dom: {
    // A hidden tab skips the transition (the browser would abort it); an aborted one
    // still applies its patch, so a sheet never waits on the animation.
    onDocumentPatch(start) {
      const go = vtNext && document.startViewTransition && !reduced() && !document.hidden
      vtNext = false
      if (vtQueue) return queue(vtQueue.then(start).catch(console.error))
      if (!go) return start()
      let done = false
      const once = () => { if (!done) { done = true; start() } }
      const vt = document.startViewTransition(once)
      vt.finished.catch(() => {})
      queue(vt.updateCallbackDone.catch(once))
    },
    onPatchEnd: () => remodal(),
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// A decision <dialog> asks to be opened (see `dialog_sheet` in core_components.ex).
// From 64rem a `data-side` dialog is a non-modal panel in the right column
// ("panel": show(), focus on its primary button) or does not open ("hidden": the
// column shows it already, so it counts as closed at once).
const wide = matchMedia("(min-width: 64rem)")
const sideOpen = d => {
  if (d.open) return
  // The books drawer stays open when a decision comes; the decision opens after it.
  const books = document.querySelector("#sheet-books:popover-open")
  if (books) return books.addEventListener("toggle", () => sideOpen(d), {once: true})
  const side = wide.matches && d.dataset.side
  if (side === "hidden") return closed(d)
  side ? d.show() : d.showModal()
}
// A closed dialog may run its `on_close` JS and hand over to the next one
// (`then_open` on `dialog_sheet`).
const closed = d => {
  const onClose = d.dataset?.onClose
  onClose && liveSocket.execJS(d, onClose)
  const next = d.dataset?.thenOpen && document.getElementById(d.dataset.thenOpen)
  next && sideOpen(next)
}
const moving = new WeakSet()
// A patch that adds or removes an element before an open <dialog> moves the dialog
// (morphdom's insertBefore). The move takes a modal dialog out of the top layer but
// keeps `open`: it is then a plain fixed box under the action bar, which takes the
// taps on its lower part (round 13). Open the modals again, in page order, so the
// last one (the new card) stays on top.
function remodal() {
  const modals = [...document.querySelectorAll("dialog[open]")].filter(d => !(wide.matches && d.dataset.side))
  if (modals.every(d => d.matches(":modal"))) return
  modals.forEach(d => { moving.add(d); d.close(); d.showModal() })
}
window.addEventListener("quacks:modal", e => sideOpen(e.target))
document.addEventListener("close", e => moving.delete(e.target) || closed(e.target), true)
// Crossing 64rem moves an open side dialog between panel and sheet.
wide.addEventListener("change", () => document.querySelectorAll("dialog[data-side=panel][open]").forEach(d => {
  moving.add(d); d.close(); sideOpen(d)
}))
// A tap on the dimmed backdrop (outside the sheet) closes a modal sheet.
document.addEventListener("click", e => {
  const d = e.target, r = d.getBoundingClientRect?.()
  if (d.tagName !== "DIALOG" || !d.matches(":modal") || !r) return
  if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) d.close()
})
// A popover sheet that closed (button, Esc or a tap outside) runs its `data-on-hide` JS.
document.addEventListener("toggle", e => {
  const onHide = e.newState === "closed" && e.target.dataset?.onHide
  onHide && liveSocket.execJS(e.target, onHide)
}, true)
// A choice inside a dialog (or popover sheet) closes it once it is sent.
window.addEventListener("quacks:close", e =>
  e.target.matches("[popover]") ? e.target.hidePopover() : e.target.close?.())
// The reveal overlay ended (round 14): the server names the dialog that waited
// for it (the shop, a decision, the game-over sheet).
window.addEventListener("phx:quacks:open", e => {
  const d = document.querySelector(e.detail.to)
  d && sideOpen(d)
})
// A tab that outlived a deploy (`QuacksWeb.StaticCheck`): reload, so the new
// stylesheet comes with the new markup. At most once a minute, so a stale cache
// cannot loop.
window.addEventListener("phx:quacks:reload", () => {
  let last = 0
  try { last = Number(sessionStorage.getItem("quacks:reloaded") || 0) } catch (_e) {}
  if (Date.now() - last < 60000) return
  try { sessionStorage.setItem("quacks:reloaded", String(Date.now())) } catch (_e) {}
  window.location.reload()
})
// The b hotkey (`hotkey` in game_live.ex): the server asks to toggle a popover sheet.
window.addEventListener("phx:quacks:toggle", e => document.getElementById(e.detail.id)?.togglePopover())
// A "Copy link" button asks for its text on the clipboard (see `copy_link` in game_live.ex).
window.addEventListener("quacks:copy", e => navigator.clipboard?.writeText(e.detail.text))

// connect if there are any LiveViews on the page
liveSocket.connect()

// PWA install. Android Chrome fires `beforeinstallprompt` only with a registered
// service worker that has a fetch handler (`/sw.js`, pass-through, no cache); then it
// can be installed: keep the event and show the lobby's `data-role=install` button.
// iOS Safari has no prompt: outside the installed app, show the Share-menu hint.
// The state is a data attribute on <html>, so LiveView patches do not reset it.
if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js")
  .then(() => window.dispatchEvent(new Event("quacks:install"))).catch(() => {})
let installPrompt = null
const installState = value => value ? document.documentElement.dataset.install = value : delete document.documentElement.dataset.install
window.addEventListener("beforeinstallprompt", e => {
  e.preventDefault(); installPrompt = e; installFired = true; installState("ready")
  window.dispatchEvent(new Event("quacks:install"))
})
window.addEventListener("appinstalled", () => { installPrompt = null; installState(null) })
document.addEventListener("click", async e => {
  if (!installPrompt || !e.target.closest("[data-role=install]")) return
  const prompt = installPrompt
  installPrompt = null
  installState(null)
  await prompt.prompt()
})
const standalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
// `navigator.standalone` exists only on iOS/iPadOS WebKit (an iPad says "Macintosh").
if (!standalone && "standalone" in navigator && navigator.maxTouchPoints > 1) installState("ios")

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

