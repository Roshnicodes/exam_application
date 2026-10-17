import { Controller } from "@hotwired/stimulus"
import { getStream, screenShareSupported, getScreenStream, requestScreen } from "lib/media"
import { loadFaceDetector } from "lib/face_detector"
import { unlockAudio } from "lib/sound"

// Pre-exam check: camera + mic permission, exactly one face, single display, full screen support.
export default class extends Controller {
  static targets = [ "video", "tag", "placeholder", "camCheck", "faceCheck", "screenCheck", "shareCheck", "shareBtn", "agree", "startBtn", "allowBtn", "form" ]

  connect() {
    this.state = { cam: false, face: false, screen: false, share: false }
    this.checkScreen()
    this.checkShare()
    loadFaceDetector() // warm up the model while the candidate reads the rules
  }

  disconnect() {
    clearInterval(this.faceTimer)
  }

  async allow() {
    try {
      const stream = await getStream()
      this.videoTarget.srcObject = stream
      this.placeholderTarget.classList.add("hidden")
      this.tagTarget.classList.remove("hidden")
      this.set("camCheck", true, "Ready")
      this.state.cam = true
      this.allowBtnTarget.classList.add("hidden")
      unlockAudio()
      this.watchFace()
    } catch (e) {
      this.set("camCheck", false, e.name === "NotAllowedError" ? "Permission denied" : "Not found")
      this.allowBtnTarget.innerHTML = "Try again"
    }
    this.refresh()
  }

  async watchFace() {
    this.set("faceCheck", null, "Loading face check…")
    const detector = await loadFaceDetector()
    if (!detector) {
      this.state.face = true
      this.set("faceCheck", true, "Skipped")
      return this.refresh()
    }
    this.faceTimer = setInterval(async () => {
      if (this.videoTarget.readyState < 2) return
      const n = await detector.count(this.videoTarget).catch(() => -1)
      if (n === 1) this.set("faceCheck", true, "1 face ✓")
      else if (n === 0) this.set("faceCheck", false, "No face")
      else if (n > 1) this.set("faceCheck", false, `${n} faces`)
      this.state.face = n === 1
      this.refresh()
    }, 700)
  }

  async checkScreen() {
    const extended = window.screen.isExtended === true
    const fs = !!document.documentElement.requestFullscreen
    this.state.screen = !extended && fs
    this.set("screenCheck", this.state.screen, extended ? "Disconnect extra display" : (fs ? "OK" : "Unsupported browser"))
    this.refresh()
  }

  // Desktop: the entire screen must be shared before starting. Phones can't share, so it's skipped there.
  checkShare() {
    if (!screenShareSupported()) {
      this.state.share = true
      this.set("shareCheck", true, "Not needed on mobile")
      this.shareBtnTarget.classList.add("hidden")
    } else if (getScreenStream()) {
      this.state.share = true
      this.set("shareCheck", true, "Shared ✓")
      this.shareBtnTarget.classList.add("hidden")
    }
    this.refresh()
  }

  async share() {
    try {
      const screen = await requestScreen()
      screen.getVideoTracks()[0].addEventListener("ended", () => {
        this.state.share = false
        this.set("shareCheck", false, "Stopped — share again")
        this.shareBtnTarget.classList.remove("hidden")
        this.refresh()
      }, { once: true })
      this.state.share = true
      this.set("shareCheck", true, "Shared ✓")
      this.shareBtnTarget.classList.add("hidden")
    } catch (e) {
      this.state.share = false
      this.set("shareCheck", false, e.name === "NotEntireScreen" ? "Choose “Entire screen”" : "Not shared")
    }
    this.refresh()
  }

  refresh() {
    const ready = this.state.cam && this.state.face && this.state.screen && this.state.share && this.agreeTarget.checked
    this.startBtnTarget.disabled = !ready
  }

  async start(event) {
    event.preventDefault()
    if (this.startBtnTarget.disabled) return
    try { await document.documentElement.requestFullscreen({ navigationUI: "hide" }) } catch {}
    clearInterval(this.faceTimer)
    this.startBtnTarget.disabled = true
    this.formTarget.requestSubmit()
  }

  set(target, ok, text) {
    const el = this[`${target}Target`]
    el.classList.toggle("ok", ok === true)
    el.classList.toggle("bad", ok === false)
    el.querySelector(".st").textContent = text
  }
}
