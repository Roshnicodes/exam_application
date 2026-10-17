import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ICE_SERVERS, newViewerId } from "lib/live_video"

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

// Meet-style interview room: everyone sees and hears everyone (WebRTC mesh, best for up to ~6 people).
export default class extends Controller {
  static targets = [ "grid", "localVideo", "micBtn", "camBtn", "status", "nameInput", "joinPanel", "room", "count" ]
  static values = { invitationId: Number, token: String, watchToken: String, name: String, needsName: Boolean, leaveUrl: String }

  connect() {
    this.peers = new Map() // peerId -> { pc, pending, tile, name, role }
    this.peerId = newViewerId()
    if (!this.needsNameValue) this.join()
  }

  disconnect() {
    this.leave(false)
  }

  // Panelists pick who they are before joining.
  joinAs(event) {
    event.preventDefault()
    const name = this.nameInputTarget.value.trim()
    if (!name) return this.nameInputTarget.focus()
    try { localStorage.setItem("panelist-name", name) } catch {}
    this.nameValue = name
    this.joinPanelTarget.classList.add("hidden")
    this.join()
  }

  async join() {
    this.roomTarget.classList.remove("hidden")
    this.setStatus("Starting camera…")
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 640 }, height: { ideal: 480 } }, audio: { echoCancellation: true, noiseSuppression: true } })
    } catch {
      this.stream = new MediaStream() // join without camera / mic (can still see and hear others)
      this.setStatus("Camera / mic blocked — you can still watch and listen")
    }
    this.localVideoTarget.srcObject = this.stream
    this.updateButtons()

    const params = { channel: "InterviewChannel", peer_id: this.peerId }
    if (this.tokenValue) params.token = this.tokenValue
    else Object.assign(params, { invitation_id: this.invitationIdValue, watch_token: this.watchTokenValue, name: this.nameValue })

    this.subscription = await cable.subscribeTo(params, {
      connected: () => this.setStatus("Connected — waiting for others to join"),
      rejected: () => this.setStatus("The interview room is not open"),
      received: (m) => this.received(m)
    })
  }

  received(message) {
    if (message.type === "peer-joined" && message.peer.id !== this.peerId) {
      this.connectTo(message.peer, true) // existing members call the newcomer
    } else if (message.type === "peer-left") {
      this.drop(message.peer_id)
    } else if (message.type === "signal") {
      this.signal(message.from, message.data)
    } else if (message.type === "media-state") {
      const peer = this.peers.get(message.peer_id)
      if (peer) {
        peer.tile.classList.toggle("muted", !message.mic)
        peer.tile.classList.toggle("cam-off", !message.cam)
      }
    }
  }

  connectTo(info, initiator) {
    let peer = this.peers.get(info.id)
    if (peer && !initiator) return peer
    if (peer) this.drop(info.id)

    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
    peer = { pc, pending: [], name: info.name, role: info.role, tile: this.addTile(info) }
    this.peers.set(info.id, peer)
    this.stream.getTracks().forEach((t) => pc.addTrack(t, this.stream))
    if (!this.stream.getAudioTracks().length) pc.addTransceiver("audio", { direction: "recvonly" })
    if (!this.stream.getVideoTracks().length) pc.addTransceiver("video", { direction: "recvonly" })

    pc.ontrack = (e) => {
      const video = peer.tile.querySelector("video")
      if (video.srcObject !== e.streams[0]) video.srcObject = e.streams[0]
      video.play().catch(() => {})
      peer.tile.classList.add("connected")
    }
    pc.onicecandidate = (e) => e.candidate && this.send(info.id, { candidate: e.candidate.toJSON() })
    pc.onconnectionstatechange = () => {
      const state = pc.connectionState
      peer.tile.dataset.state = state
      clearTimeout(peer.dropTimer)
      if (this.peers.get(info.id)?.pc !== pc) return
      if (state === "closed") {
        this.drop(info.id)
      } else if (state === "failed" || state === "disconnected") {
        // a participant who left without a goodbye (closed tab, lost network) disappears after a grace period
        peer.tile.querySelector(".it-note").textContent = state === "failed" ? "Connection lost" : "Reconnecting…"
        peer.tile.classList.remove("connected")
        peer.dropTimer = setTimeout(() => { if (this.peers.get(info.id)?.pc === pc) this.drop(info.id) }, state === "failed" ? 4000 : 10000)
      } else if (state === "connected") {
        peer.tile.classList.add("connected")
      }
    }

    if (initiator) {
      pc.createOffer().then((offer) => pc.setLocalDescription(offer))
        .then(() => this.send(info.id, { sdp: pc.localDescription.toJSON() }))
    }
    this.refreshCount()
    this.announceMedia()
    return peer
  }

  async signal(from, data) {
    const peer = this.connectTo(from, false)
    if (data.sdp) {
      await peer.pc.setRemoteDescription(data.sdp)
      for (const c of peer.pending.splice(0)) await peer.pc.addIceCandidate(c).catch(() => {})
      if (data.sdp.type === "offer") {
        await peer.pc.setLocalDescription(await peer.pc.createAnswer())
        this.send(from.id, { sdp: peer.pc.localDescription.toJSON() })
      }
    } else if (data.candidate) {
      if (peer.pc.remoteDescription) await peer.pc.addIceCandidate(data.candidate).catch(() => {})
      else peer.pending.push(data.candidate)
    }
  }

  addTile(info) {
    const tile = document.createElement("div")
    tile.className = `it-tile role-${info.role}`
    tile.innerHTML = `
      <video autoplay playsinline></video>
      <div class="it-placeholder"><span class="avatar">${esc(info.name.split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase())}</span><span class="it-note">Connecting…</span></div>
      <span class="it-name">${esc(info.name)} <em>${esc({ candidate: "Candidate", hr: "HR", panelist: "Panelist" }[info.role] || "")}</em></span>
      <span class="it-mic-off" title="Muted">🔇</span>`
    this.gridTarget.appendChild(tile)
    return tile
  }

  drop(peerId) {
    const peer = this.peers.get(peerId)
    if (!peer) return
    clearTimeout(peer.dropTimer)
    peer.pc.close()
    peer.tile.remove()
    this.peers.delete(peerId)
    this.refreshCount()
  }

  send(to, data) {
    this.subscription?.perform("signal", { to, data })
  }

  toggleMic() {
    this.stream?.getAudioTracks().forEach((t) => (t.enabled = !t.enabled))
    this.updateButtons()
    this.announceMedia()
  }

  toggleCam() {
    this.stream?.getVideoTracks().forEach((t) => (t.enabled = !t.enabled))
    this.updateButtons()
    this.announceMedia()
  }

  announceMedia() {
    const mic = this.stream?.getAudioTracks().some((t) => t.enabled) || false
    const cam = this.stream?.getVideoTracks().some((t) => t.enabled) || false
    this.subscription?.perform("media_state", { mic, cam })
  }

  updateButtons() {
    const mic = this.stream?.getAudioTracks().some((t) => t.enabled)
    const cam = this.stream?.getVideoTracks().some((t) => t.enabled)
    this.micBtnTarget.classList.toggle("off", !mic)
    this.micBtnTarget.querySelector("span").textContent = mic ? "Mute" : "Unmute"
    this.camBtnTarget.classList.toggle("off", !cam)
    this.camBtnTarget.querySelector("span").textContent = cam ? "Stop video" : "Start video"
    this.element.querySelector(".it-self")?.classList.toggle("cam-off", !cam)
  }

  refreshCount() {
    const n = this.peers.size + 1
    if (this.hasCountTarget) this.countTarget.textContent = `${n} in the room`
    this.gridTarget.dataset.count = n
    if (this.peers.size) this.setStatus("")
  }

  leave(redirect = true) {
    this.peers.forEach((_, id) => this.drop(id))
    this.subscription?.unsubscribe()
    this.subscription = null
    this.stream?.getTracks().forEach((t) => t.stop())
    if (redirect && this.leaveUrlValue) window.Turbo.visit(this.leaveUrlValue)
  }

  setStatus(text) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = text
      this.statusTarget.classList.toggle("hidden", !text)
    }
  }
}
