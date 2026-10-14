// Round 45: a chip turns into a bigger one (Nick: "animate into the larger one and
// play the new sound"). The old chip grows and fades; the new one grows in from
// small with the chips' spring pop. WAAPI `transform`/`opacity` only, on two nodes
// that sit on the same place: a copy of the old chip (out of LiveView's way) and
// the new chip. SVG or HTML: the scale is about each node's own origin (a pot chip
// is drawn about 0 0; `.chip-morph` sets the centre for an HTML chip).
//
// Users: `PotMotion` (app.js: Chicken eyes, AB1, the copper witch and the purple
// book IV change a pot chip in place) and the `ChipMorph`
// hook below (any HTML chip whose `data-chip` changes, e.g. a later upgrade pane).

const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const easing = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

// The total length in ms; the new chip's sound fits best at `MORPH_PEAK`.
export const MORPH_MS = 480
export const MORPH_PEAK = 220

// Plays the morph. Resolves when it ends (the caller removes the old copy then).
// Reduced motion: a 180 ms crossfade, no scale.
export const morphChip = (oldNode, newNode) => {
  oldNode.getAnimations?.().forEach(a => a.cancel())
  newNode.getAnimations?.().forEach(a => a.cancel())
  if (reduced()) {
    newNode.animate([{opacity: 0}, {opacity: 1}], {duration: 180, easing: "ease"})
    return oldNode.animate([{opacity: 1}, {opacity: 0}], {duration: 180, easing: "ease", fill: "forwards"})
      .finished.catch(() => {})
  }
  const out = easing("--ease-out")
  newNode.animate([
    {transform: "scale(0.6)", opacity: 0, easing: out},
    {transform: "scale(1.22)", opacity: 1, offset: 0.55, easing: easing("--ease-spring")},
    {transform: "scale(1)", opacity: 1},
  ], {duration: MORPH_MS - 120, delay: 120, fill: "backwards"})
  return oldNode.animate([
    {transform: "scale(1)", opacity: 1, easing: out},
    {transform: "scale(1.15)", opacity: 1, offset: 0.4, easing: out},
    {transform: "scale(1.4)", opacity: 0},
  ], {duration: 300, fill: "forwards"}).finished.catch(() => {})
}

// The hook: an HTML chip (`data-chip`, e.g. "green-2") that becomes another chip
// morphs into it; with `data-sound`, its sound plays at the peak. Usage:
// `<span id=... phx-hook="ChipMorph" data-chip="green-2" data-sound=...><.chip .../></span>`.
export const ChipMorph = (play) => ({
  mounted() { this.keep() },
  beforeUpdate() { this.keep() },
  updated() {
    const was = this.was
    this.keep()
    if (!was || was.key === this.el.dataset.chip) return
    const copy = was.node
    copy.removeAttribute("id")
    copy.classList.add("chip-morph-old")
    this.el.append(copy)
    morphChip(copy, this.el.firstElementChild).then(() => copy.remove())
    play(this.el.dataset.sound, {delay: reduced() ? 0 : MORPH_PEAK / 1000})
  },
  keep() {
    const face = this.el.firstElementChild
    this.was = face && {key: this.el.dataset.chip, node: face.cloneNode(true)}
  },
})
