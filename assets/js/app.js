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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ConfigMemory},
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

