import { Controller } from "@hotwired/stimulus"
import { getStream, snapshot, csrfToken } from "lib/media"
import { loadFaceDetector, loadObjectDetector } from "lib/face_detector"
import { warningBeep, unlockAudio } from "lib/sound"
import { Broadcaster } from "lib/live_video"

const MESSAGES = {
  tab_switch: "You switched tabs or minimized the window.",
  window_blur: "The exam window lost focus. Stay on this screen.",
  fullscreen_exit: "You exited full screen mode.",
  no_face: "Your face is not visible. Stay in front of the camera.",
  multiple_faces: "More than one person detected in the camera.",
  camera_off: "Your camera was turned off or blocked.",
  copy_paste: "Copy / paste is not allowed during the exam.",
  right_click: "Right click is disabled during the exam.",
  devtools: "Restricted keyboard shortcut detected.",
  screenshot: "Screenshots are not allowed.",
  noise: "Talking or loud background noise detected.",
  screen_share_stopped: "You stopped sharing your screen. Share your entire screen again to continue.",
  screen_not_entire: "Please share your entire screen, not a single window or tab.",
  multiple_displays: "A second display is connected. Disconnect it.",
  looking_away: "Please look at the screen. Turning away or looking down is not allowed.",
  face_movement: "Too much movement detected. Sit still and stay centred in the camera.",
  eyes_away: "Keep your eyes on the screen. Looking down or away (e.g. at a phone) is not allowed.",
  phone_detected: "A mobile phone, book or other device was detected. Remove it from your desk."
}
const COOLDOWN = { eyes_away: 10000, phone_detected: 15000, looking_away: 10000, face_movement: 10000, no_face: 12000, noise: 45000, multiple_faces: 12000, window_blur: 8000, default: 6000 }
const SEGMENT_MS = 60_000
const SNAPSHOT_MS = 30_000

// Watches the candidate: camera recording, face detection, focus / full screen / keyboard activity.
export default class extends Controller {
  static targets = [ "video", "faceStatus", "warnLabel", "warning", "warningText", "warningDots", "warningLeft", "fullscreenGate", "cameraGate" ]
  static values = { eventsUrl: String, recordingsUrl: String, warnings: Number, maxWarnings: Number, token: String,
                    mode: { type: String, default: "exam" } }

  // In an interview the checks start once the candidate is in the room (after screen sharing),
  // so the share picker or the join click can't be mistaken for leaving the window.
  connect() {
    this.onExternalViolation = (e) => this.violation(e.detail.kind, e.detail.message)
    window.addEventListener("proctor:violation", this.onExternalViolation)
    if (this.interview) {
      this.onReady = () => this.begin()
      window.addEventListener("interview:ready", this.onReady, { once: true })
    } else {
      this.begin()
    }
  }

  get interview() {
    return this.modeValue === "interview"
  }

  async begin() {
    if (this.started) return
    this.started = true
    this.active = true
    this.lastFired = {}
    this.uploads = new Set()
    this.segmentIndex = 0
    this.bindListeners()
    this.checkFullscreen()

    if (!(await this.attachCamera())) return
    this.startMonitoring()
  }

  async attachCamera() {
    try {
      this.stream = await getStream()
      this.cameraGateTarget.classList.add("hidden")
      return true
    } catch {
      this.setFace("bad", "Camera blocked — allow camera access")
      this.cameraGateTarget.classList.remove("hidden")
      this.violation("camera_off", "Camera permission denied", { overlay: false })
      return false
    }
  }

  async retryCamera() {
    if (await this.attachCamera()) this.startMonitoring()
  }

  startMonitoring() {
    if (!this.interview) this.startLiveFeed() // the interview room already streams the camera
    if (this.monitoring) return
    this.monitoring = true
    this.videoTarget.srcObject = this.stream
    this.stream.getTracks().forEach((t) => t.addEventListener("ended", this.onTrackEnded))

    this.startSegment()
    this.startFaceDetection()
    this.startObjectDetection()
    if (!this.interview) this.startNoiseMonitor() // talking is the point of an interview
    this.snapshotTimer = setInterval(() => this.report("snapshot"), SNAPSHOT_MS)
    setTimeout(() => this.report("snapshot"), 4000)
    if (window.screen.isExtended) this.violation("multiple_displays")
  }

  disconnect() {
    window.removeEventListener("proctor:violation", this.onExternalViolation)
    window.removeEventListener("interview:ready", this.onReady)
    this.broadcaster?.stop()
    this.active = false
    this.unbindListeners()
    clearInterval(this.faceTimer)
    clearInterval(this.objectTimer)
    clearInterval(this.snapshotTimer)
    clearInterval(this.noiseTimer)
    clearTimeout(this.segmentTimer)
  }

  // Live camera for HR / panelists (WebRTC). Failure here never blocks the exam.
  startLiveFeed() {
    if (!this.hasTokenValue || !window.RTCPeerConnection) return
    try {
      if (this.broadcaster) return this.broadcaster.setStream(this.stream)
      this.broadcaster = new Broadcaster(this.tokenValue)
      this.broadcaster.start(this.stream).catch((e) => console.warn("Live feed unavailable", e))
    } catch (e) {
      console.warn("Live feed unavailable", e)
    }
  }

  // ---------------------------------------------------------------- listeners
  bindListeners() {
    this.onVisibility = () => { if (document.hidden) this.violation("tab_switch") }
    this.onBlur = () => setTimeout(() => {
      if (!document.hidden && !document.hasFocus()) this.violation("window_blur")
    }, 400)
    this.onFullscreen = () => this.checkFullscreen(true)
    this.onClipboard = (e) => { e.preventDefault(); this.violation("copy_paste", `${e.type} attempt`) }
    this.onContext = (e) => { e.preventDefault(); this.violation("right_click") }
    this.onKey = (e) => this.handleKey(e)
    this.onKeyUp = (e) => { if (e.key === "PrintScreen") { navigator.clipboard?.writeText("").catch(() => {}); this.violation("screenshot") } }
    this.onBeforeUnload = (e) => { if (this.active) { e.preventDefault(); e.returnValue = "" } }
    this.onTrackEnded = () => {
      if (!this.active) return
      this.setFace("bad", "Camera stopped!")
      this.violation("camera_off", null, { overlay: false })
      this.monitoring = false
      clearInterval(this.faceTimer)
      clearInterval(this.objectTimer)
      clearInterval(this.noiseTimer)
      clearInterval(this.snapshotTimer)
      this.closeSegment()
      this.cameraGateTarget.classList.remove("hidden")
    }

    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("blur", this.onBlur)
    document.addEventListener("fullscreenchange", this.onFullscreen)
    ;[ "copy", "cut", "paste" ].forEach((t) => document.addEventListener(t, this.onClipboard))
    document.addEventListener("contextmenu", this.onContext)
    document.addEventListener("keydown", this.onKey, true)
    document.addEventListener("keyup", this.onKeyUp, true)
    window.addEventListener("beforeunload", this.onBeforeUnload)
  }

  unbindListeners() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("blur", this.onBlur)
    document.removeEventListener("fullscreenchange", this.onFullscreen)
    ;[ "copy", "cut", "paste" ].forEach((t) => document.removeEventListener(t, this.onClipboard))
    document.removeEventListener("contextmenu", this.onContext)
    document.removeEventListener("keydown", this.onKey, true)
    document.removeEventListener("keyup", this.onKeyUp, true)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    this.stream?.getTracks().forEach((t) => t.removeEventListener("ended", this.onTrackEnded))
  }

  handleKey(e) {
    const k = e.key.toLowerCase()
    const mod = e.ctrlKey || e.metaKey
    if (k === "f12" || (mod && e.shiftKey && [ "i", "j", "c", "k" ].includes(k)) || (mod && [ "u", "s", "p" ].includes(k))) {
      e.preventDefault()
      return this.violation("devtools", `Pressed ${e.ctrlKey ? "Ctrl+" : ""}${e.metaKey ? "Cmd+" : ""}${e.shiftKey ? "Shift+" : ""}${e.key}`)
    }
    if (mod && [ "c", "v", "x" ].includes(k)) {
      e.preventDefault()
      return this.violation("copy_paste", `Pressed ${e.ctrlKey ? "Ctrl" : "Cmd"}+${e.key.toUpperCase()}`)
    }
    if (k === "printscreen" || (e.metaKey && e.shiftKey && [ "3", "4", "5", "s" ].includes(k))) {
      return this.violation("screenshot")
    }
  }

  // ---------------------------------------------------------------- full screen
  checkFullscreen(changed = false) {
    if (this.interview && !document.documentElement.requestFullscreen) return // e.g. iPhone Safari
    const inFs = !!document.fullscreenElement
    this.fullscreenGateTarget.classList.toggle("hidden", inFs || !this.active)
    if (changed && !inFs) this.violation("fullscreen_exit")
  }

  async enterFullscreen() {
    unlockAudio()
    try { await document.documentElement.requestFullscreen({ navigationUI: "hide" }) } catch {}
    this.checkFullscreen()
  }

  // ---------------------------------------------------------------- face detection
  async startFaceDetection() {
    this.setFace("idle", "Loading face detection…")
    const detector = await loadFaceDetector()
    if (!this.active) return
    if (!detector) {
      this.setFace("idle", "Face detection unavailable")
      return this.report("detector_unavailable")
    }

    let noFaceSince = null
    let multiStreak = 0
    this.pose = { baseline: [], awayStreak: 0, gazeStreak: 0, edgeStreak: 0, moves: [], last: null }
    this.faceTimer = setInterval(async () => {
      if (!this.active || this.videoTarget.readyState < 2) return
      const faces = await detector.detect(this.videoTarget).catch((e) => { console.warn("Face detection failed", e); return null })
      if (!faces) {
        this.detectFailures = (this.detectFailures || 0) + 1
        if (this.detectFailures === 5) {
          this.setFace("idle", "Face detection error")
          this.report("detector_unavailable", "Detection keeps failing on this device")
        }
        return
      }
      this.detectFailures = 0
      const n = faces.length

      if (n === 0) {
        noFaceSince ||= Date.now()
        this.pose.last = null
        this.setFace("bad", "Face not visible")
        if (Date.now() - noFaceSince > 3000) this.violation("no_face")
        return
      }
      noFaceSince = null

      if (n > 1) {
        multiStreak += 1
        this.setFace("bad", `${n} faces detected!`)
        if (multiStreak >= 2) this.violation("multiple_faces", `${n} faces in frame`)
        return
      }
      multiStreak = 0

      this.checkPose(faces[0])
    }, 700)
  }

  // Head direction + movement for a single face. Thresholds are relative to the
  // candidate's own baseline (first few frames), so camera angle doesn't matter.
  checkPose(face) {
    const p = this.pose
    const b = face.box
    const cx = b.x + b.w / 2
    const cy = b.y + b.h / 2
    let yaw = null
    let pitch = null
    if (face.keypoints.length >= 4) {
      const [ re, le, nose, mouth ] = face.keypoints
      const eyeX = (re.x + le.x) / 2
      const eyeY = (re.y + le.y) / 2
      const eyeDist = Math.hypot(le.x - re.x, le.y - re.y) || 0.001
      yaw = (nose.x - eyeX) / eyeDist
      const span = mouth.y - eyeY
      pitch = span > 0.001 ? (nose.y - eyeY) / span : null
    }

    // 1. learn the neutral pose from the first frames
    if (p.baseline.length < 6) {
      if (yaw !== null && pitch !== null && Math.abs(yaw) < 0.3) p.baseline.push({ yaw, pitch, gaze: face.gaze })
      this.setFace("idle", "Calibrating — look at the screen")
      p.last = { cx, cy, w: b.w }
      return
    }
    const base = {
      yaw: p.baseline.reduce((s, x) => s + x.yaw, 0) / p.baseline.length,
      pitch: p.baseline.reduce((s, x) => s + x.pitch, 0) / p.baseline.length
    }

    // 2. head turned left/right or looking down/up
    let away = null
    if (yaw !== null) {
      const dy = yaw - base.yaw
      if (Math.abs(dy) > 0.3) away = dy > 0 ? "Head turned left" : "Head turned right" // camera image is not mirrored
    }
    if (!away && pitch !== null) {
      const dp = pitch - base.pitch
      if (dp > 0.2) away = "Looking down"
      else if (dp < -0.2) away = "Looking up"
    }
    p.awayStreak = away ? p.awayStreak + 1 : 0
    if (p.awayStreak >= 3) this.violation("looking_away", away) // ~2s

    // 2b. eyes looking down / sideways / closed while the head stays still (e.g. a phone in the lap)
    const eyes = !away && face.gaze ? this.checkGaze(face.gaze, p.baseline) : null
    p.gazeStreak = eyes ? p.gazeStreak + 1 : 0
    if (p.gazeStreak >= 3) this.violation("eyes_away", eyes) // ~2s

    // 3. face leaving the frame
    const atEdge = b.x < 0.01 || b.y < 0.01 || b.x + b.w > 0.99 || b.y + b.h > 0.99 || Math.abs(cx - 0.5) > 0.3
    p.edgeStreak = atEdge ? p.edgeStreak + 1 : 0
    if (p.edgeStreak >= 3) this.violation("face_movement", "Moving out of the camera frame")

    // 4. lots of sudden movement (3 big jumps within 6s)
    const now = Date.now()
    if (p.last) {
      const jump = Math.hypot(cx - p.last.cx, cy - p.last.cy) + Math.abs(b.w - p.last.w)
      if (jump > 0.09) p.moves.push(now)
    }
    p.last = { cx, cy, w: b.w }
    p.moves = p.moves.filter((t) => now - t < 6000)
    if (p.moves.length >= 3) {
      p.moves = []
      this.violation("face_movement", "Too much head / body movement")
    }

    if (away) this.setFace("bad", `${away} — look at the screen`)
    else if (eyes) this.setFace("bad", `${eyes} — keep eyes on screen`)
    else if (atEdge) this.setFace("bad", "Stay centred in the camera")
    else this.setFace("ok", "Face verified")
  }

  // Eye direction relative to the candidate's own calibrated gaze.
  checkGaze(g, baseline) {
    const base = (key) => {
      const vals = baseline.map((b) => b.gaze?.[key]).filter((v) => typeof v === "number")
      return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : 0
    }
    if (g.closed > 0.6 && g.down > 0.25) return "Eyes looking down"
    if (g.closed > 0.75) return "Eyes closed"
    if (g.down > 0.45 && g.down - base("down") > 0.22) return "Eyes looking down"
    if (g.left > 0.5 && g.left - base("left") > 0.25) return "Eyes looking left"
    if (g.right > 0.5 && g.right - base("right") > 0.25) return "Eyes looking right"
    if (g.up > 0.55 && g.up - base("up") > 0.25) return "Eyes looking up"
    return null
  }

  // Phones, books or another screen in view (checked every ~1.5s, needs 2 hits in a row).
  async startObjectDetection() {
    const detector = await loadObjectDetector()
    if (!detector || !this.active) return

    let streak = 0
    let busy = false
    this.objectTimer = setInterval(async () => {
      if (busy || !this.active || this.videoTarget.readyState < 2) return
      busy = true
      try {
        const found = await detector.detect(this.videoTarget)
        streak = found.length ? streak + 1 : 0
        if (found.length) this.setFace("bad", `${found[0].label} detected!`)
        if (streak >= 2) {
          const labels = [ ...new Set(found.map((f) => f.label)) ].join(", ")
          this.violation("phone_detected", `${labels} (${Math.round(found[0].score * 100)}% sure)`)
        }
      } catch (e) {
        console.warn("Object detection failed", e)
      } finally {
        busy = false
      }
    }, 1500)
  }

  setFace(state, text) {
    const el = this.faceStatusTarget
    el.classList.toggle("bad", state === "bad")
    el.classList.toggle("idle", state === "idle")
    el.querySelector("span").textContent = text
  }

  // ---------------------------------------------------------------- noise
  startNoiseMonitor() {
    if (!this.stream.getAudioTracks().length) return
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      const analyser = ctx.createAnalyser()
      analyser.fftSize = 1024
      ctx.createMediaStreamSource(this.stream).connect(analyser)
      const buf = new Float32Array(analyser.fftSize)
      let loud = 0
      this.noiseTimer = setInterval(() => {
        if (ctx.state === "suspended") ctx.resume()
        analyser.getFloatTimeDomainData(buf)
        const rms = Math.sqrt(buf.reduce((s, v) => s + v * v, 0) / buf.length)
        loud = rms > 0.12 ? loud + 1 : Math.max(0, loud - 1)
        if (loud >= 8) { loud = 0; this.violation("noise") } // ~2s of sustained sound
      }, 250)
    } catch (e) {
      console.warn("Noise monitor unavailable", e)
    }
  }

  // ---------------------------------------------------------------- recording
  startSegment() {
    if (!this.active || !window.MediaRecorder) return
    const type = [ "video/webm;codecs=vp8,opus", "video/webm", "video/mp4" ].find((t) => MediaRecorder.isTypeSupported(t))
    const recorder = new MediaRecorder(this.stream, { mimeType: type, videoBitsPerSecond: 350_000, audioBitsPerSecond: 48_000 })
    const chunks = []
    const stopped = new Promise((resolve) => (recorder.onstop = resolve))
    recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data)
    recorder.start(1000)
    this.segment = { recorder, chunks, stopped, type: recorder.mimeType || type }
    this.segmentTimer = setTimeout(() => this.rotateSegment(), SEGMENT_MS)
  }

  rotateSegment() {
    this.closeSegment()
    this.startSegment()
  }

  async closeSegment() {
    const seg = this.segment
    if (!seg) return
    this.segment = null
    clearTimeout(this.segmentTimer)
    if (seg.recorder.state !== "inactive") seg.recorder.stop()
    await seg.stopped
    if (!seg.chunks.length) return

    const body = new FormData()
    body.append("segment", new Blob(seg.chunks, { type: seg.type }), `segment.${seg.type.includes("mp4") ? "mp4" : "webm"}`)
    body.append("index", this.segmentIndex++)
    const upload = fetch(this.recordingsUrlValue, { method: "POST", headers: { "X-CSRF-Token": csrfToken() }, body })
      .catch((e) => console.warn("Recording upload failed", e))
    this.uploads.add(upload)
    upload.finally(() => this.uploads.delete(upload))
    return upload
  }

  // Called by the exam controller right before submitting.
  finish(event) {
    this.active = false
    this.unbindListeners()
    clearInterval(this.faceTimer)
    clearInterval(this.objectTimer)
    clearInterval(this.noiseTimer)
    clearInterval(this.snapshotTimer)
    this.fullscreenGateTarget.classList.add("hidden")
    this.cameraGateTarget.classList.add("hidden")
    this.broadcaster?.stop()
    const done = this.closeSegment().then(() => Promise.allSettled([ ...this.uploads ]))
    event.detail.waits.push(done)
  }

  // ---------------------------------------------------------------- violations
  violation(kind, detail, { overlay = true } = {}) {
    if (!this.active || this.active === "terminated") return
    const now = Date.now()
    if (now - (this.lastFired[kind] || 0) < (COOLDOWN[kind] || COOLDOWN.default)) return
    this.lastFired[kind] = now

    this.warningsValue += 1
    warningBeep()
    this.flashScreen()
    if (overlay) this.showWarning(MESSAGES[kind] || "Suspicious activity detected.")
    this.report(kind, detail)
  }

  async report(kind, message) {
    const body = new FormData()
    body.append("kind", kind)
    if (message) body.append("message", message)
    const shot = await snapshot(this.videoTarget, kind === "snapshot" ? 0.6 : 0.75)
    if (shot) body.append("snapshot", shot, `${kind}.jpg`)

    try {
      const res = await fetch(this.eventsUrlValue, { method: "POST", headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" }, body })
      if (!res.ok) return
      const data = await res.json()
      if (typeof data.warnings === "number") this.warningsValue = data.warnings
      if (data.terminated && this.active !== "terminated") {
        this.active = "terminated"
        this.dispatch("terminated", { detail: { redirect: data.redirect } })
      }
    } catch (e) {
      console.warn("Could not report event", e)
    }
  }

  warningsValueChanged() {
    if (!this.hasWarnLabelTarget) return
    this.warnLabelTarget.textContent = this.maxWarningsValue > 0 ? `${this.warningsValue}/${this.maxWarningsValue}` : this.warningsValue
  }

  showWarning(text) {
    this.warningTextTarget.textContent = text
    const max = this.maxWarningsValue
    if (max > 0) {
      this.warningDotsTarget.innerHTML = Array.from({ length: max }, (_, i) => `<i class="${i < this.warningsValue ? "on" : ""}"></i>`).join("")
      const left = Math.max(0, max - this.warningsValue)
      this.warningLeftTarget.textContent = left > 0
        ? `${left} warning${left === 1 ? "" : "s"} left before your exam is ended automatically. HR has been notified.`
        : "Warning limit reached. Your exam is being submitted."
    } else {
      this.warningLeftTarget.textContent = this.interview ? "The interview panel has been alerted." : "HR has been notified of this activity."
    }
    this.warningTarget.classList.remove("hidden")
  }

  dismissWarning() {
    this.warningTarget.classList.add("hidden")
    if (!document.fullscreenElement) this.enterFullscreen()
  }

  flashScreen() {
    const el = document.createElement("div")
    el.className = "screen-flash"
    document.body.appendChild(el)
    setTimeout(() => el.remove(), 1300)
  }
}
