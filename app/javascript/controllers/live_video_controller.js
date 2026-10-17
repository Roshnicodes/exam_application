import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ICE_SERVERS, newViewerId } from "lib/live_video"

// Viewer side (HR / panelist): shows the candidate's live camera, like a video call.
export default class extends Controller {
  static targets = [ "video", "status", "sound", "frame", "screen" ]
  static values = { invitationId: Number, watchToken: String }

  async connect() {
    this.viewerId = newViewerId()
    this.pending = []
    this.setStatus("connecting", "Connecting…")
    this.subscription = await cable.subscribeTo(
      { channel: "LiveVideoChannel", role: "viewer", invitation_id: this.invitationIdValue, viewer_id: this.viewerId, watch_token: this.watchTokenValue },
      {
        connected: () => this.waitForCandidate(),
        rejected: () => this.setStatus("offline", "No access to this live feed"),
        received: (message) => this.received(message)
      }
    )
  }

  disconnect() {
    clearTimeout(this.offlineTimer)
    clearTimeout(this.fallbackTimer)
    this.closePeer()
    this.subscription?.unsubscribe()
  }

  waitForCandidate() {
    this.setStatus("connecting", "Waiting for the candidate's camera…")
    clearTimeout(this.offlineTimer)
    this.offlineTimer = setTimeout(() => {
      if (!this.live) this.setStatus("offline", "Candidate is not in the exam right now")
    }, 8000)
  }

  received(message) {
    if (message.type === "frame") return this.showFrame(message.image)
    if (message.type === "candidate-ready") {
      this.subscription.perform("hello")
      this.waitForCandidate()
    } else if (message.type === "candidate-left") {
      this.closePeer()
      this.hideFrame()
      this.setStatus("offline", "Candidate left the exam")
    } else if (message.type === "signal") {
      this.signal(message.data)
    }
  }

  async signal(data) {
    if (data?.sdp) {
      this.closePeer()
      this.screenId = data.screen || null
      const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
      this.pc = pc
      // no direct video within 10s (blocked network) -> switch to the backup frames
      clearTimeout(this.fallbackTimer)
      this.fallbackTimer = setTimeout(() => { if (!this.live) this.useFrames() }, 10000)
      pc.ontrack = (e) => {
        if (this.screenId && e.streams[0]?.id === this.screenId) return this.showScreen(e.streams[0])
        this.videoTarget.srcObject = e.streams[0]
        this.videoTarget.play().catch(() => {})
        this.live = true
        this.hideFrame()
        this.setStatus("live", "LIVE")
      }
      pc.onicecandidate = (e) => e.candidate && this.subscription.perform("signal", { data: { candidate: e.candidate.toJSON() } })
      pc.onconnectionstatechange = () => {
        if (pc.connectionState === "failed") { this.live = false; this.useFrames() }
        if (pc.connectionState === "disconnected") this.setStatus("connecting", "Reconnecting…")
        if (pc.connectionState === "connected") this.setStatus("live", "LIVE")
      }
      await pc.setRemoteDescription(data.sdp)
      for (const c of this.pending.splice(0)) await pc.addIceCandidate(c).catch(() => {})
      await pc.setLocalDescription(await pc.createAnswer())
      this.subscription.perform("signal", { data: { sdp: pc.localDescription.toJSON() } })
    } else if (data?.candidate) {
      if (this.pc?.remoteDescription) await this.pc.addIceCandidate(data.candidate).catch(() => {})
      else this.pending.push(data.candidate)
    }
  }

  // Backup view over the websocket: works on any network, ~1 picture per second, no audio.
  useFrames() {
    if (this.usingFrames) return
    this.usingFrames = true
    this.subscription?.perform("want_frames")
    this.setStatus("connecting", "Switching to backup view…")
  }

  showFrame(image) {
    if (this.live || !this.usingFrames) return
    if (!this.hasFrameTarget) {
      const img = document.createElement("img")
      img.className = "lv-frame"
      img.alt = "Candidate camera (backup view)"
      img.dataset.liveVideoTarget = "frame"
      this.element.prepend(img)
    }
    this.frameTarget.src = image
    this.frameTarget.hidden = false
    this.setStatus("live", "LIVE · backup view")
  }

  hideFrame() {
    this.usingFrames = false
    if (this.hasFrameTarget) this.frameTarget.hidden = true
  }

  toggleSound() {
    this.videoTarget.muted = !this.videoTarget.muted
    if (this.hasSoundTarget) this.soundTarget.textContent = this.videoTarget.muted ? "🔇 Unmute" : "🔊 Mute"
  }

  // The candidate's shared screen: shown big, with the camera as a small inset.
  showScreen(stream) {
    if (!this.hasScreenTarget) return // compact monitor tiles show the camera only
    this.screenTarget.srcObject = stream
    this.screenTarget.hidden = false
    this.screenTarget.play().catch(() => {})
    this.element.classList.add("has-screen")
  }

  closePeer() {
    if (this.hasScreenTarget) {
      this.screenTarget.srcObject = null
      this.screenTarget.hidden = true
    }
    this.element.classList.remove("has-screen")
    this.pc?.close()
    this.pc = null
    this.live = false
    this.pending = []
    if (this.hasVideoTarget) this.videoTarget.srcObject = null
  }

  setStatus(state, text) {
    this.element.dataset.liveState = state
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
