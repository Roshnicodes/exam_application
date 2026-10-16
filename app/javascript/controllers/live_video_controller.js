import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ICE_SERVERS, newViewerId } from "lib/live_video"

// Viewer side (HR / panelist): shows the candidate's live camera, like a video call.
export default class extends Controller {
  static targets = [ "video", "status", "sound" ]
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
    if (message.type === "candidate-ready") {
      this.subscription.perform("hello")
      this.waitForCandidate()
    } else if (message.type === "candidate-left") {
      this.closePeer()
      this.setStatus("offline", "Candidate left the exam")
    } else if (message.type === "signal") {
      this.signal(message.data)
    }
  }

  async signal(data) {
    if (data?.sdp) {
      this.closePeer()
      const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
      this.pc = pc
      pc.ontrack = (e) => {
        this.videoTarget.srcObject = e.streams[0]
        this.videoTarget.play().catch(() => {})
        this.live = true
        this.setStatus("live", "LIVE")
      }
      pc.onicecandidate = (e) => e.candidate && this.subscription.perform("signal", { data: { candidate: e.candidate.toJSON() } })
      pc.onconnectionstatechange = () => {
        if (pc.connectionState === "failed") this.setStatus("offline", "Connection failed — the network may be blocking video")
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

  toggleSound() {
    this.videoTarget.muted = !this.videoTarget.muted
    if (this.hasSoundTarget) this.soundTarget.textContent = this.videoTarget.muted ? "🔇 Unmute" : "🔊 Mute"
  }

  closePeer() {
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
