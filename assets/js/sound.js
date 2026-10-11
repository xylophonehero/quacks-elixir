// Game sounds (docs/research/sounds.md, QuacksWeb.Sounds). One AudioContext, made
// and unlocked on the first gesture; the files (`<body data-sounds>`, name => URL)
// are decoded once, after the unlock. A few sounds are synths (no file). Settings
// in localStorage["quacks:sound"]: {v: 1, on, volume}. Sound only adds to what the
// page shows: a sound that is not ready, or one over the voice limit, drops.

const DEFAULTS = {v: 1, on: true, volume: 0.7}
// The level of each sound (the user's volume is on top). Chip sounds: `chip`.
const GAINS = {boom: 1, ruby: 0.6, gameover: 0.5, fortune: 0.6, chip: 0.5, plop: 0.6, bloop: 0.6, chime: 0.6}
const MAX_VOICES = 4

export const loadSound = () => {
  try {
    const s = JSON.parse(localStorage.getItem("quacks:sound"))
    return s && s.v === 1 ? {...DEFAULTS, ...s} : {...DEFAULTS}
  } catch (_e) { return {...DEFAULTS} }
}
const saveSound = s => { try { localStorage.setItem("quacks:sound", JSON.stringify({...s, v: 1})) } catch (_e) {} }

let ctx = null, master = null, noiseBuf = null, idle = null
const buffers = new Map(), loading = new Map(), last = new Map(), voices = new Set()
const files = () => { try { return JSON.parse(document.body?.dataset.sounds || "{}") } catch (_e) { return {} } }

const load = name => {
  if (!loading.has(name)) {
    const url = files()[name]
    const p = !url ? Promise.resolve(null) : fetch(url)
      .then(r => r.ok ? r.arrayBuffer() : Promise.reject(new Error(`${url}: ${r.status}`)))
      .then(b => new Promise((ok, no) => ctx.decodeAudioData(b, ok, no)))
      .then(buf => { buffers.set(name, buf); return buf })
      .catch(e => { console.warn("sound", name, e); return null })
    loading.set(name, p)
  }
  return loading.get(name)
}

// In a gesture: make the context (iOS "ambient": the silent switch mutes it, and
// the user's music plays on), start the decoding, and resume it.
export const unlock = () => {
  if (!loadSound().on) return
  if (!ctx) {
    const AC = window.AudioContext || window.webkitAudioContext
    if (!AC) return
    try { if (navigator.audioSession) navigator.audioSession.type = "ambient" } catch (_e) {}
    ctx = new AC()
    master = ctx.createGain()
    master.connect(ctx.destination)
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate / 2, ctx.sampleRate)
    const d = noiseBuf.getChannelData(0)
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1
    Object.keys(files()).forEach(load)
  }
  if (ctx.state !== "running") {
    // The old iOS trick: a 1-sample silent buffer in the gesture.
    const s = ctx.createBufferSource()
    s.buffer = ctx.createBuffer(1, 1, 22050)
    s.connect(ctx.destination)
    s.start()
    ctx.resume().catch(() => {})
  }
}

;["pointerup", "touchend", "keydown"].forEach(t => addEventListener(t, unlock, {capture: true, passive: true}))
document.addEventListener("visibilitychange", () => {
  if (!ctx) return
  if (document.hidden) ctx.suspend().catch(() => {})
  else if (loadSound().on) ctx.resume().catch(() => {})
})

// ---- synths (the sound demo's, scratchpad sounds/demo) ----
const env = (g, t, peak, attack, decay) => {
  g.gain.setValueAtTime(0.0001, t)
  g.gain.exponentialRampToValueAtTime(peak, t + attack)
  g.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay)
}
const tone = (out, t, from, to, glide, peak, attack, decay) => {
  const o = ctx.createOscillator(), g = ctx.createGain()
  o.type = "sine"
  o.frequency.setValueAtTime(from, t)
  if (to) o.frequency.exponentialRampToValueAtTime(to, t + glide)
  env(g, t, peak, attack, decay)
  o.connect(g).connect(out)
  o.start(t)
  o.stop(t + attack + decay + 0.05)
}
const hiss = (out, t, peak, freq, dur) => {
  const s = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain()
  s.buffer = noiseBuf
  f.type = "highpass"
  f.frequency.value = freq
  env(g, t, peak, 0.002, dur)
  s.connect(f).connect(g).connect(out)
  s.start(t, Math.random() * 0.3)
  s.stop(t + dur + 0.05)
}
// Each takes the start time, the voice's gain node and the pitch factor, and
// gives the length in seconds.
const SYNTHS = {
  // D5: the water drop, a sine that glides up fast.
  plop(t, out, p) { tone(out, t, 280 * p, 950 * p, 0.07, 0.7, 0.004, 0.09); return 0.15 },
  // L4: a deeper bloop with a small splash (the droplet moves).
  bloop(t, out, p) {
    tone(out, t, 180 * p, 520 * p, 0.11, 0.8, 0.006, 0.14)
    hiss(out, t + 0.01, 0.12, 3000, 0.06)
    return 0.2
  },
  // A placeholder for the fortune teller's crystal ball: three glassy sines.
  chime(t, out, p) {
    ;[[1318.5, 0, 0.6], [1760, 0.09, 0.55], [2637, 0.18, 0.5]].forEach(([f, d, decay]) =>
      tone(out, t + d, f * p, null, 0, 0.3, 0.004, decay))
    return 0.8
  },
}

const gainOf = name => GAINS[name.startsWith("chip-") ? "chip" : name] ?? 0.5

// The explosion stops the small sounds that still play (30 ms fade).
const duck = t => voices.forEach(v => {
  v.gain.gain.cancelScheduledValues(t)
  v.gain.gain.setTargetAtTime(0, t, 0.01)
})

const start = (name, delay, pitch, gain) => {
  const synth = SYNTHS[name], buf = buffers.get(name)
  if (!synth && !buf) return
  const big = name === "boom"
  if (!big && voices.size >= MAX_VOICES) return
  const t = ctx.currentTime + delay
  // The same sound twice in 50 ms is one sound.
  if (Math.abs((last.get(name) ?? -1) - t) < 0.05) return
  last.set(name, t)
  if (big) duck(t)
  master.gain.value = loadSound().volume
  const g = ctx.createGain()
  g.gain.value = gainOf(name) * gain * (0.9 + Math.random() * 0.2)
  g.connect(master)
  const p = 1 + (Math.random() * 2 - 1) * pitch
  let length
  if (synth) length = synth(t, g, p)
  else {
    const src = ctx.createBufferSource()
    src.buffer = buf
    src.playbackRate.value = p
    src.connect(g)
    src.start(t)
    length = buf.duration / p
  }
  const voice = {gain: g}
  if (!big) voices.add(voice)
  setTimeout(() => { voices.delete(voice); g.disconnect() }, (delay + length) * 1000 + 100)
  // No sound for 30 s: let the audio hardware sleep (the next play resumes it).
  clearTimeout(idle)
  idle = setTimeout(() => { if (ctx.state === "running" && voices.size === 0) ctx.suspend().catch(() => {}) }, 30000)
}

// play("boom") or play("chip-white-1", {delay: 0.368}). `wait`: a sound that is
// still decoding plays when it is ready (the gallery's buttons, the settings'
// preview), instead of dropping.
export const play = (name, {delay = 0, pitch = 0.04, gain = 1, wait = false} = {}) => {
  if (!name || !ctx || document.hidden || !loadSound().on) return
  const go = () => start(name, delay, pitch, gain)
  const ready = SYNTHS[name] || buffers.has(name)
  if (!ready && !wait) return
  const decoded = ready ? Promise.resolve() : load(name)
  if (ctx.state === "running" && ready) return go()
  Promise.all([decoded, ctx.resume()]).then(go).catch(() => {})
}

// The gallery's Sounds story: `JS.dispatch("quacks:sound", detail: %{name: ...})`.
window.addEventListener("quacks:sound", e => { unlock(); play(e.detail?.name, {wait: true}) })

// The menu's Sound row (`SoundComponents.sound_settings/1`): sets the saved values
// on mount, saves each change, and plays a preview at the new volume.
export const SoundSettings = {
  mounted() {
    const s = loadSound()
    const check = (name, value) => {
      const input = this.el.querySelector(`input[name="${name}"][value="${value}"]`)
      if (input) input.checked = true
    }
    check("on", s.on ? "on" : "off")
    const volumes = [...this.el.querySelectorAll("input[name=volume]")].map(i => +i.value)
    check("volume", volumes.reduce((a, b) => Math.abs(b - s.volume) < Math.abs(a - s.volume) ? b : a, 0.7))
    this.el.addEventListener("change", () => {
      const form = new FormData(this.el)
      const next = {on: form.get("on") !== "off", volume: +(form.get("volume") || DEFAULTS.volume)}
      saveSound(next)
      if (!next.on) return ctx?.suspend().catch(() => {})
      unlock()
      play(this.el.dataset.preview || "plop", {wait: true, pitch: 0})
    })
  }
}

// The large pot's sounds (app.js `PotMotion`), your own pot only (`data-mine`;
// the bots' draws are silent). Reduced motion: no flight, so at once.
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const beatMs = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--beat-ms")) || 450
export const potSound = {
  // Your draw, as the chip lands (offset 0.8 of the 460 ms flight). None when the
  // chip exploded the pot: the explosion plays (`Boom`).
  draw(pot, chip) {
    if (pot.dataset.exploded !== "true") play(chip.dataset.sound, {delay: reduced() ? 0 : 0.368})
  },
  // Your droplet moved (`was` its old space): the bloop as it lands. After a ruby
  // hop (520 ms), or on its line's beat in the scoring sequence (the CSS slide,
  // `data-slide-beat`).
  drop(pot, was) {
    const d = pot.querySelector("[data-role=droplet]")
    if (!pot.dataset.mine || !d || d.dataset.index === was) return
    const step = beatMs(), beat = pot.dataset.slideBeat
    const ms = d.dataset.hop ? 440 : beat ? step * 2 / 3 + beat * step + 200 : 200
    play("bloop", {delay: reduced() ? 0 : ms / 1000})
  },
  // The glass "ting" as a ruby reaches the counter (`at` ms).
  ruby(pot, at) {
    if (pot.dataset.mine) play("ruby", {delay: reduced() ? 0 : at / 1000, pitch: 0.03})
  },
}

// `SoundComponents.sound_cue/1`: one sound when the element mounts; with
// `data-once`, once per tab (a reload does not play it again).
export const SoundCue = {
  mounted() {
    const once = this.el.dataset.once
    if (once) {
      const key = `quacks:sound:${once}`
      try { if (sessionStorage.getItem(key)) return; sessionStorage.setItem(key, "1") } catch (_e) {}
    }
    play(this.el.dataset.sound, {delay: (+this.el.dataset.delay || 0) / 1000, pitch: 0})
  }
}

// The scoring replay (`Sounds.replay/2`): on a black, green or purple book step,
// each row's chip sound as its result lands (app.css `.results-stage .stage-got`:
// 240 ms), one row after the other on a third of a beat.
export const SoundReplay = {
  mounted() {
    let cues = []
    try { cues = JSON.parse(this.el.dataset.cues || "[]") } catch (_e) {}
    const beat = beatMs()
    cues.forEach(([i, name]) => play(name, {delay: ((reduced() ? 0 : 240) + i * beat / 3) / 1000, pitch: 0.02}))
  }
}
