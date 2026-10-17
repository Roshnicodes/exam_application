// Synthesised alert sounds (Web Audio), so no audio files are needed.
// All of them are soft bell-like tones: noticeable, but never harsh.
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

function ready() {
  const c = audioContext()
  if (c.state !== "running") c.resume()
  return c
}

// A bell-like note: quick soft attack, natural fade-out, plus a quiet overtone for warmth.
function bell(freq, start, { duration = 0.6, volume = 0.16, type = "sine" } = {}) {
  const c = audioContext()
  const out = c.createGain()
  out.gain.setValueAtTime(0.0001, start)
  out.gain.exponentialRampToValueAtTime(volume, start + 0.015)
  out.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  out.connect(c.destination)

  ;[ [ freq, type, 1 ], [ freq * 2, "sine", 0.25 ] ].forEach(([ f, wave, level ]) => {
    const osc = c.createOscillator()
    const gain = c.createGain()
    osc.type = wave
    osc.frequency.value = f
    gain.gain.value = level
    osc.connect(gain).connect(out)
    osc.start(start)
    osc.stop(start + duration + 0.05)
  })
}

// Candidate warning: a gentle two-note "ding-dong".
export function warningBeep() {
  const c = ready()
  const t = c.currentTime + 0.02
  bell(1318.5, t, { duration: 0.45, volume: 0.18, type: "triangle" }) // E6
  bell(1046.5, t + 0.28, { duration: 0.7, volume: 0.16, type: "triangle" }) // C6
}

// OTP request / normal alert for HR: a soft modern phone ring (two short trills).
export function phoneRing({ times = 2 } = {}) {
  const c = ready()
  let t = c.currentTime + 0.02
  for (let r = 0; r < times; r++) {
    for (let i = 0; i < 4; i++) {
      bell(i % 2 ? 1108.7 : 880, t + i * 0.11, { duration: 0.22, volume: 0.12 }) // A5 / C#6 trill
    }
    t += 1.1
  }
}

// Serious alert for HR (two faces, camera off, phone, termination):
// a rising three-note chime played twice — urgent, but not a siren.
export function siren() {
  const c = ready()
  const t = c.currentTime + 0.02
  const notes = [ 784, 1046.5, 1318.5 ] // G5 C6 E6
  for (let round = 0; round < 2; round++) {
    notes.forEach((f, i) => bell(f, t + round * 0.75 + i * 0.13, { duration: 0.5, volume: 0.15, type: "triangle" }))
  }
}

// Informational events (exam started / submitted, sound switched on).
export function chime() {
  const c = ready()
  const t = c.currentTime + 0.02
  bell(880, t, { duration: 0.5, volume: 0.1 })
  bell(1318.5, t + 0.15, { duration: 0.8, volume: 0.09 })
}
