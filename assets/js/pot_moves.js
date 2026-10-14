// Round 45: PotMotion's moves for a chip that changes or goes back (app.js spreads
// them into the hook, so `this` is the hook: `ghost`, `top`, `pos`, `centre`, `bag`).
// The bag bumps as chips land in it; the flask tips and pours; a pot chip swapped in
// place morphs into the new one (`morphChip`). Round 46: the purple book IV's chip
// too: it stays in the pot until the round's chips go back (`PotComponents.held/2`).
import {morphChip, MORPH_PEAK} from "./chip_morph"

const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const easing = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

export const potMoves = playSound => ({
  // Round 45: the bag button takes the chips in: a small swell as they land.
  bump(delay) {
    const bag = this.bag()
    if (!bag || reduced()) return
    bag.animate([{scale: 1}, {scale: 1.1, offset: 0.4}, {scale: 1}],
      {duration: 280, delay, easing: easing("--ease-out")})
  },
  // Round 45, the flask: it tips toward the pot and pours (its old brew drains), and the white
  // chip flies back into the bag. Reduced motion: the chip fades, no tip.
  useFlask(chip) {
    const tilt = this.el.querySelector("[data-role=flask-tilt]")
    if (this.el.dataset.mine) playSound(this.el.dataset.flaskSound, {pitch: 0.02})
    this.ghost(chip, this.centre(this.bag()), reduced() ? 0 : 140)
    if (reduced() || !tilt) return
    this.bump(400)
    const tip = a => `translate(0px, 30px) rotate(${a}deg) translate(0px, -30px)`
    tilt.animate([
      {transform: tip(0), easing: easing("--ease-out")},
      {transform: tip(26), offset: 0.35, easing: easing("--ease-in-out")},
      {transform: tip(-8), offset: 0.75, easing: easing("--ease-out")},
      {transform: tip(0)},
    ], {duration: 600})
    const brew = this.brew, body = tilt.querySelector(".flask-body")
    if (!brew || !body) return
    body.after(brew)
    brew.firstElementChild.animate([{transform: "translateY(0px)"}, {transform: "translate(6px, 36px)"}],
      {duration: 420, delay: 60, easing: easing("--ease-in-out"), fill: "forwards"})
      .finished.catch(() => {}).finally(() => brew.remove())
  },
  // Round 45: a pot chip swapped in place grows into the new chip (`morphChip`),
  // and the new chip's sound plays (your own pot).
  swap(chip) {
    const old = this.keys.get(chip.id).copy
    const g = this.top(old, this.pos(chip.dataset.index))
    morphChip(old, chip).then(() => g.remove())
    if (this.el.dataset.mine) playSound(chip.dataset.sound, {delay: reduced() ? 0 : MORPH_PEAK / 1000, pitch: 0})
  },
})
