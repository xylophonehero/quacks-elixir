// The card table's hooks (Hearts first; `TableWeb.Components.*`).
//
// TableTheme: the viewer's theme and deck colours, kept in localStorage.
// TableMotion: FLIP motion between two renders of a table. It needs only DOM data
// (see `TableWeb.Components.Cards`):
//   - `[data-flip][id]`: a card or a back. The same id in a new place slides there.
//   - a new one with `data-from="<id>"` flies in from that element;
//   - one that goes away with `data-to="<id>"` (on the render before) flies there
//     as a copy and fades;
//   - `data-flip-delay="<ms>"` starts it later.
// WAAPI on `translate`, `scale`, `rotate` and `opacity` only (the compositor). The
// face inside a card keeps its own `translate` for the lift, so they do not fight.
// No `phx-update="ignore"` on the table: WAAPI writes no attributes. The copies go
// into the table's `<id>-fx` box, which LiveView ignores. The table is a size
// container, so it is the containing block of the copies: their place is relative to the box.

const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const easing = name =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim() || "ease-out"
const centre = r => ({x: r.left + r.width / 2, y: r.top + r.height / 2})
const angle = v => (v && v !== "none" ? v : "0deg")
const xy = v => {
  if (!v || v === "none") return [0, 0]
  const [x = "0", y = "0"] = v.split(" ")
  return [parseFloat(x) || 0, parseFloat(y) || 0]
}
// A card's own width: the element's, or the first card's in a container.
const cardWidth = el => {
  if (!el) return 0
  const card = el.matches(".tb-card") ? el : el.querySelector(".tb-card")
  return (card || el).offsetWidth
}

const FLY = 420
const TAG = "tb-motion"

export const TableMotion = {
  mounted() { this.snap() },
  beforeUpdate() { this.snap() },
  updated() { this.play() },

  // What the motion needs from the render before: where each card was.
  snap() {
    this.prev = new Map()
    this.el.querySelectorAll("[data-flip][id], [data-anchor][id]").forEach(el => {
      const flip = el.hasAttribute("data-flip")
      this.prev.set(el.id, {
        rect: el.getBoundingClientRect(),
        w: cardWidth(el),
        rotate: flip ? angle(getComputedStyle(el).rotate) : "0deg",
        to: el.dataset.to,
        delay: +(el.dataset.flipDelay || 0),
        node: flip && el.dataset.to ? el.cloneNode(true) : null,
      })
    })
  },

  play() {
    const prev = this.prev || new Map()
    const now = [...this.el.querySelectorAll("[data-flip][id]")]
    const ids = new Set(now.map(el => el.id))
    now.forEach(el => el.getAnimations().forEach(a => a.id === TAG && a.cancel()))
    const calm = reduced()

    for (const el of now) {
      const before = prev.get(el.id)
      const delay = +(el.dataset.flipDelay || 0)
      if (before) {
        this.move(el, before, delay, calm)
      } else if (el.dataset.from) {
        const from = el.dataset.from, was = prev.get(from), live = document.getElementById(from)
        this.enter(el, was?.rect || live?.getBoundingClientRect(), was?.w || cardWidth(live), delay, calm)
      }
    }
    for (const [id, before] of prev) {
      if (!ids.has(id) && before.node && before.to) this.leave(before, before.delay, calm)
    }
  },

  // The same card in a new place: from the old place to the new one.
  move(el, before, delay, calm) {
    if (calm) return
    const cs = getComputedStyle(el)
    const now = el.getBoundingClientRect()
    const a = centre(before.rect), b = centre(now)
    const [tx, ty] = xy(cs.translate)
    const dx = a.x - b.x, dy = a.y - b.y
    const s = before.w && el.offsetWidth ? before.w / el.offsetWidth : 1
    const rot = angle(cs.rotate)
    if (Math.abs(dx) < 1 && Math.abs(dy) < 1 && Math.abs(s - 1) < 0.01 && rot === before.rotate) return
    el.animate([
      {translate: `${tx + dx}px ${ty + dy}px`, scale: s, rotate: before.rotate},
      {translate: `${tx}px ${ty}px`, scale: 1, rotate: rot},
    ], {duration: FLY, delay, easing: easing("--ease-out"), fill: "backwards", id: TAG})
  },

  // A new card: it flies in from `from` (the deck, a hand), small as a card there.
  enter(el, from, fromW, delay, calm) {
    if (calm || !from) {
      el.animate([{opacity: 0}, {opacity: 1}],
        {duration: 150, delay: calm ? delay / 4 : delay, easing: "ease", fill: "backwards", id: TAG})
      return
    }
    const cs = getComputedStyle(el)
    const now = el.getBoundingClientRect()
    const a = centre(from), b = centre(now)
    const [tx, ty] = xy(cs.translate)
    const s = fromW && el.offsetWidth ? fromW / el.offsetWidth : 1
    const rot = angle(cs.rotate)
    el.animate([
      {translate: `${tx + a.x - b.x}px ${ty + a.y - b.y}px`, scale: s, rotate: "0deg", opacity: 0.6},
      {opacity: 1, offset: 0.25},
      {translate: `${tx}px ${ty}px`, scale: 1, rotate: rot, opacity: 1},
    ], {duration: FLY, delay, easing: easing("--ease-out"), fill: "backwards", id: TAG})
  },

  // A card that left: a copy flies from its old place to `to` and fades there.
  leave(before, delay, calm) {
    const target = document.getElementById(before.to)
    const box = this.el.querySelector(`#${CSS.escape(this.el.id)}-fx`)
    if (!target || !box) return
    const g = before.node
    const w = before.w, h = w * 1.4
    const c = centre(before.rect), o = box.getBoundingClientRect()
    g.removeAttribute("id")
    g.removeAttribute("data-flip")
    g.removeAttribute("data-state")
    g.className = "tb-card tb-ghost"
    g.style.cssText = `left:${c.x - o.left - w / 2}px; top:${c.y - o.top - h / 2}px; width:${w}px; --card-w:${w}px; rotate:${before.rotate}`
    box.append(g)
    const t = centre(target.getBoundingClientRect())
    const s = cardWidth(target) && w ? cardWidth(target) / w : 0.5
    const done = () => g.remove()
    if (calm) {
      g.animate([{opacity: 1}, {opacity: 0}], {duration: 150, easing: "ease", fill: "forwards"}).finished.then(done, done)
      return
    }
    g.animate([
      {translate: "0px 0px", scale: 1, rotate: before.rotate, opacity: 1},
      {translate: `${t.x - c.x}px ${t.y - c.y}px`, scale: s, rotate: "0deg", opacity: 1, offset: 0.8},
      {translate: `${t.x - c.x}px ${t.y - c.y}px`, scale: s * 0.9, rotate: "0deg", opacity: 0},
    ], {duration: FLY + 80, delay, easing: easing("--ease-in-out"), fill: "backwards"}).finished.then(done, done)
  },
}

// The theme and the deck colours of a `.tb-root` with `phx-hook="TableTheme"`.
const KEYS = {theme: "table:theme", deck: "table:deck"}
const load = key => { try { return localStorage.getItem(key) } catch { return null } }
const save = (key, value) => { try { localStorage.setItem(key, value) } catch { /* private mode */ } }

export const TableTheme = {
  mounted() {
    const themes = (this.el.dataset.themes || "").split(" ")
    const theme = load(KEYS.theme), deck = load(KEYS.deck)
    this.apply({
      theme: themes.includes(theme) ? theme : null,
      deck: deck === "2" || deck === "4" ? deck : null,
    })
    this.el.addEventListener("table:pick", e => {
      const pick = {...e.detail}
      if (pick.deck === "toggle") pick.deck = this.el.dataset.deck === "4" ? "2" : "4"
      this.apply(pick)
      if (pick.theme) save(KEYS.theme, pick.theme)
      if (pick.deck) save(KEYS.deck, pick.deck)
    })
  },
  updated() { this.apply({}) },
  apply({theme, deck}) {
    if (theme) this.el.dataset.theme = theme
    if (deck) this.el.dataset.deck = deck
    this.el.querySelectorAll("[data-pick-theme]").forEach(b =>
      b.setAttribute("aria-pressed", String(b.dataset.pickTheme === this.el.dataset.theme)))
    this.el.querySelectorAll("[data-pick-deck]").forEach(b =>
      b.setAttribute("aria-pressed", String(this.el.dataset.deck === "4")))
  },
}
