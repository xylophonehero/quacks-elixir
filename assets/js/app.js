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

// The large pot's motion (docs/research/animations.md §3 B3, round 10). Every patch
// already shows the final pot; this only plays WAAPI `transform`/`opacity` on top, so
// it never holds up a tap. A new chip drops in on its own space (from 1.3× and a
// little above, then the pop); a chip that leaves flies as a ghost to the flask (or
// the bag); at a new round the old chips fade. New rats pop in place (CSS
// `chip-land`). Reduced motion: fades only.
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const easing = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()
const at = (p, o, s = 1) => `translate(${p.x - o.x}px, ${p.y - o.y}px) scale(${s})`

const PotMotion = {
  // Running animations go on through later patches (a bot's draw is a patch too):
  // WAAPI writes no attributes, and each chip keeps its node.
  mounted() { this.snapshot() },
  beforeUpdate() { this.snapshot() },
  updated() {
    const chips = [...this.el.querySelectorAll("[data-role=pot-chip]")]
    const added = chips.filter(c => !this.chips.has(c.id))
    const gone = [...this.chips.values()].filter(c => !c.isConnected)
    const flask = this.full && !this.el.querySelector("[data-role=flask-brew]")
    if (this.el.dataset.round !== this.round)
      gone.sort((a, b) => a.dataset.order - b.dataset.order).forEach((c, i) => this.ghost(c, null, i * 20))
    else if (gone.length === 1 && added.length === 0)
      this.ghost(gone[0], this.centre(flask ? this.el.querySelector("[data-role=flask]") : this.bag()))
    else if (added.length <= 2) added.forEach(c => this.land(c))
    this.snapshot()
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

