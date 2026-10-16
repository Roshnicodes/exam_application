// Synthesised alert sounds (Web Audio) so no audio files are needed.
let ctx

export function audioContext() {
  ctx ||= new (window.AudioContext || window.webkitAudioContext)()
  return ctx
}

export async function unlockAudio() {
  const c = audioContext()
  if (c.state === "suspended") await c.resume()
  return c.state === "running"
}

function tone(freqs, start, duration, { type = "sine", volume = 0.18 } = {}) {
  const c = audioContext()
  const gain = c.createGain()
  gain.gain.setValueAtTime(0, start)
  gain.gain.linearRampToValueAtTime(volume, start + 0.02)
  gain.gain.setValueAtTime(volume, start + duration - 0.04)
  gain.gain.linearRampToValueAtTime(0, start + duration)
  gain.connect(c.destination)
  ;[].concat(freqs).forEach((f) => {
    const osc = c.createOscillator()
    osc.type = type
    osc.frequency.value = f
    osc.connect(gain)
    osc.start(start)
    osc.stop(start + duration)
  })
}

// Short triple beep for the candidate when a warning fires.
export function warningBeep() {
  const c = audioContext()
  if (c.state !== "running") c.resume()
  const t = c.currentTime + 0.02
  for (let i = 0; i < 3; i++) tone(988, t + i * 0.22, 0.14, { type: "square", volume: 0.12 })
}

// Classic two-tone telephone ring for HR (two rings, ~2.6s).
export function phoneRing({ times = 2 } = {}) {
  const c = audioContext()
  if (c.state !== "running") c.resume()
  let t = c.currentTime + 0.02
  for (let r = 0; r < times; r++) {
    tone([ 440, 480 ], t, 0.4, { volume: 0.22 })
    tone([ 440, 480 ], t + 0.6, 0.4, { volume: 0.22 })
    t += 1.6
  }
}

// Rising siren for critical events (multiple faces, camera off, termination).
export function siren() {
  const c = audioContext()
  if (c.state !== "running") c.resume()
  const t = c.currentTime + 0.02
  const osc = c.createOscillator()
  const gain = c.createGain()
  osc.type = "sawtooth"
  gain.gain.value = 0.08
  for (let i = 0; i < 4; i++) {
    osc.frequency.setValueAtTime(600, t + i * 0.5)
    osc.frequency.linearRampToValueAtTime(1200, t + i * 0.5 + 0.45)
  }
  osc.connect(gain).connect(c.destination)
  osc.start(t)
  osc.stop(t + 2)
}

// Soft chime for informational events.
export function chime() {
  const c = audioContext()
  if (c.state !== "running") c.resume()
  const t = c.currentTime + 0.02
  tone(660, t, 0.18, { volume: 0.12 })
  tone(880, t + 0.16, 0.28, { volume: 0.12 })
}
