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

// The large pot's motion (docs/research/animations.md §3 B3). Every patch already
// shows the final pot; this only plays WAAPI `transform`/`opacity` on top, so it
// never holds up a tap. A new chip flies out of the bag, hops along the spiral and
// lands with a pop; a chip that leaves flies as a ghost to the flask (or the bag);
// the rat stone hops; at a new round the old chips fade. Reduced motion: fades only.
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const easing = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()
const at = (p, o, s = 1) => `translate(${p.x - o.x}px, ${p.y - o.y}px) scale(${s})`
// At most `n` of the spaces strictly between `from` and `to`, evenly spread.
const between = (from, to, n) => {
  const gap = Math.abs(to - from) - 1, dir = Math.sign(to - from), k = Math.min(n, gap)
  return Array.from({length: k}, (_, i) => from + dir * Math.round(((i + 1) * (gap + 1)) / (k + 1)))
}

const PotMotion = {
  mounted() { this.anims = new Set(); this.snapshot() },
  beforeUpdate() { this.anims.forEach(a => a.finish()); this.snapshot() },
  updated() {
    const chips = [...this.el.querySelectorAll("[data-role=pot-chip]")]
    const added = chips.filter(c => !this.chips.has(c.id))
    const gone = [...this.chips.values()].filter(c => !c.isConnected)
    const flask = this.full && !this.el.querySelector("[data-role=flask-brew]")
    const rat = this.el.querySelector("[data-role=rat-stone]")
    if (this.el.dataset.round !== this.round)
      gone.sort((a, b) => a.dataset.order - b.dataset.order).forEach((c, i) => this.ghost(c, null, i * 20))
    else if (gone.length === 1 && added.length === 0)
      this.ghost(gone[0], this.centre(flask ? this.el.querySelector("[data-role=flask]") : this.bag()))
    else if (added.length <= 2) added.forEach(c => this.fly(c, chips))
    if (rat && rat.dataset.index !== this.rat) this.hop(rat, this.droplet())
    this.snapshot()
  },
  snapshot() {
    this.chips = new Map([...this.el.querySelectorAll("[data-role=pot-chip]")].map(c => [c.id, c]))
    this.rat = this.el.querySelector("[data-role=rat-stone]")?.dataset.index
    this.full = !!this.el.querySelector("[data-role=flask-brew]")
    this.round = this.el.dataset.round
  },
  play(el, frames, opts) {
    const a = el.animate(frames, opts)
    this.anims.add(a)
    a.finished.catch(() => {}).finally(() => this.anims.delete(a))
    return a
  },
  pos(i) { const g = this.el.querySelector(`[data-space="${i}"]`).dataset; return {x: +g.x, y: +g.y} },
  droplet() { return this.el.querySelector("[data-role=droplet]").dataset.index },
  bag() { return document.querySelector("[data-role=bag-button]") },
  // An element's centre in the pot's SVG units; the lower right corner without one.
  centre(el) {
    const r = el?.getBoundingClientRect()
    if (!r?.width) return {x: 230, y: 230}
    return new DOMPoint(r.x + r.width / 2, r.y + r.height / 2).matrixTransform(this.el.getScreenCTM().inverse())
  },
  fly(chip, chips) {
    if (reduced()) return
    const to = +chip.dataset.index, end = this.pos(to)
    const lower = chips.map(c => +c.dataset.index).filter(i => i < to)
    const start = this.el.querySelector("[data-role=rat-stone]")?.dataset.index ?? this.droplet()
    const from = lower.length ? Math.max(...lower) : +start
    const pts = [this.centre(this.bag()), this.pos(from), ...between(from, to, 3).map(i => this.pos(i)), end]
    const segs = pts.slice(1).map((_, i) => (i === 0 ? 240 : 80)), total = segs.reduce((a, b) => a + b) + 160
    let t = 0
    const frames = pts.map((p, i) => {
      const f = {transform: at(p, end, i === 0 ? 0.9 : 1), opacity: i === 0 ? 0 : 1, offset: t / total,
        easing: i === 0 ? easing("--ease-out") : easing("--ease-in-out")}
      t += segs[i] ?? 0
      return f
    })
    Object.assign(frames.at(-1), {transform: at(end, end, 1.08), easing: easing("--ease-spring")})
    chip.getAnimations().forEach(a => a.cancel())
    this.play(chip, [...frames, {transform: at(end, end), opacity: 1, offset: 1}], {duration: total})
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
    this.play(el, frames, {duration: fade ? 180 : 260, delay, fill: "backwards", easing: easing("--ease-out")})
      .finished.catch(() => {}).finally(() => g.remove())
  },
  // From the droplet, one small arc per space counted (at most 5 shown).
  hop(rat, from) {
    if (reduced()) return
    const to = +rat.dataset.index, end = this.pos(to), up = easing("--ease-out")
    const pts = [this.pos(from), ...between(+from, to, 4).map(i => this.pos(i)), end]
    const frames = pts.flatMap((p, i) => {
      if (i === 0) return [{transform: at(p, end), easing: up}]
      const q = pts[i - 1], mid = {x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 - 14}
      return [{transform: at(mid, end), easing: easing("--ease-in-out")}, {transform: at(p, end), easing: up}]
    })
    rat.getAnimations().forEach(a => a.cancel())
    this.play(rat, frames, {duration: 120 * (pts.length - 1)})
  },
}

let vtNext = false, vtQueue = null
window.addEventListener("phx:quacks:vt", () => { vtNext = true })
const queue = p => { vtQueue = p; p.then(() => { if (vtQueue === p) vtQueue = null }) }

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ConfigMemory, NameMemory, PotMotion},
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
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// A decision <dialog> asks to be opened (see `dialog_sheet` in core_components.ex).
window.addEventListener("quacks:modal", e => e.target.open || e.target.showModal())
// A closed dialog may run its `on_close` JS and hand over to the next one
// (`then_open` on `dialog_sheet`).
document.addEventListener("close", e => {
  const onClose = e.target.dataset?.onClose
  onClose && liveSocket.execJS(e.target, onClose)
  const next = e.target.dataset?.thenOpen && document.getElementById(e.target.dataset.thenOpen)
  next && !next.open && next.showModal()
}, true)
// A popover sheet that closed (button, Esc or a tap outside) runs its `data-on-hide` JS.
document.addEventListener("toggle", e => {
  const onHide = e.newState === "closed" && e.target.dataset?.onHide
  onHide && liveSocket.execJS(e.target, onHide)
}, true)
// A choice inside a dialog (or popover sheet) closes it once it is sent.
window.addEventListener("quacks:close", e =>
  e.target.matches("[popover]") ? e.target.hidePopover() : e.target.close?.())
// A "Copy link" button asks for its text on the clipboard (see `copy_link` in game_live.ex).
window.addEventListener("quacks:copy", e => navigator.clipboard?.writeText(e.detail.text))

// connect if there are any LiveViews on the page
liveSocket.connect()

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

