import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ICE_SERVERS, newViewerId } from "lib/live_video"
import { getStream } from "lib/media"
import { warningBeep } from "lib/sound"

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

// Meet-style interview room: everyone sees and hears everyone (WebRTC mesh, best for up to ~6 people).
export default class extends Controller {
  static targets = [ "grid", "localVideo", "micBtn", "camBtn", "status", "nameInput", "joinPanel", "room", "count",
                     "screenGate", "screenError", "alerts" ]
  static values = { roundId: Number, token: String, watchToken: String, name: String, needsName: Boolean, leaveUrl: String }

  connect() {
    this.peers = new Map() // peerId -> { pc, pending, tile, name, role, screenStreamId, screenTile }
    this.peerId = newViewerId()
    if (this.candidate && this.screenShareSupported) return this.screenGateTarget.classList.remove("hidden")
    if (!this.needsNameValue) this.join()
  }

  get candidate() {
    return this.hasTokenValue && this.tokenValue !== ""
  }

  // Phones / tablets can't share their screen; desktops must.
  get screenShareSupported() {
    return !!navigator.mediaDevices?.getDisplayMedia && !/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent)
  }

  // ---- Candidate: share the entire screen before joining -------------------
  async shareScreen() {
    this.screenErrorTarget.textContent = ""
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({ video: { displaySurface: "monitor", frameRate: 5 }, audio: false, monitorTypeSurfaces: "include", selfBrowserSurface: "exclude" })
      const track = stream.getVideoTracks()[0]
      const surface = track.getSettings().displaySurface
      if (surface && surface !== "monitor") {
        stream.getTracks().forEach((t) => t.stop())
        this.screenErrorTarget.textContent = "Please choose “Entire screen” (not a window or a tab)."
        window.dispatchEvent(new CustomEvent("proctor:violation", { detail: { kind: "screen_not_entire", message: `Picked a ${surface}` } }))
        return
      }
      track.addEventListener("ended", () => this.screenStopped())
      const first = !this.screenStream
      this.screenStream = stream
      this.screenGateTarget.classList.add("hidden")
      document.documentElement.requestFullscreen?.({ navigationUI: "hide" }).catch(() => {})
      if (first) {
        await this.join()
      } else {
        // re-shared after stopping: swap the track in every connection, no reconnect needed
        this.peers.forEach((peer) => peer.screenSender?.replaceTrack(track))
      }
    } catch (e) {
      this.screenErrorTarget.textContent = "Screen sharing is required to join. Click the button and choose “Entire screen”."
    }
  }

  screenStopped() {
    if (!this.subscription) return
    window.dispatchEvent(new CustomEvent("proctor:violation", { detail: { kind: "screen_share_stopped", message: "Screen sharing was turned off" } }))
    this.screenGateTarget.classList.remove("hidden")
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
      this.stream = this.candidate ? await getStream()
        : await navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 640 }, height: { ideal: 480 } }, audio: { echoCancellation: true, noiseSuppression: true } })
      if (!this.candidate && !this.screenShareSupported) this.stream.getVideoTracks()[0]?.applyConstraints?.({ facingMode: "user" })
    } catch {
      this.stream = new MediaStream() // join without camera / mic (can still see and hear others)
      this.setStatus("Camera / mic blocked — you can still watch and listen")
    }
    this.localVideoTarget.srcObject = this.stream
    this.updateButtons()

    const params = { channel: "InterviewChannel", peer_id: this.peerId }
    if (this.tokenValue) params.token = this.tokenValue
    else Object.assign(params, { round_id: this.roundIdValue, watch_token: this.watchTokenValue, name: this.nameValue })

    if (this.candidate) window.dispatchEvent(new Event("interview:ready")) // start proctoring now that we're in

    this.subscription = await cable.subscribeTo(params, {
      connected: () => this.setStatus("Connected — waiting for others to join"),
      rejected: () => this.setStatus("The interview room is not open"),
      received: (m) => this.received(m)
    })
  }

  received(message) {
    if (message.type === "peer-joined" && message.peer.id !== this.peerId) {
      if (this.candidate) this.connectTo(message.peer, true) // the candidate always calls
      else if (message.peer.role === "candidate") this.send(message.peer.id, { hello: true }) // ask the candidate to call us
      else this.connectTo(message.peer, true) // between panel members, existing ones call the newcomer
    } else if (message.type === "proctor-alert") {
      if (!this.candidate) this.showAlert(message)
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
    const screenTrack = this.screenStream?.getVideoTracks()[0]
    if (screenTrack) peer.screenSender = pc.addTrack(screenTrack, this.screenStream)
    if (!this.stream.getAudioTracks().length) pc.addTransceiver("audio", { direction: "recvonly" })
    if (!this.stream.getVideoTracks().length) pc.addTransceiver("video", { direction: "recvonly" })

    pc.ontrack = (e) => {
      if (peer.screenStreamId && e.streams[0]?.id === peer.screenStreamId) return this.showScreen(peer, e.streams[0])
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
        .then(() => this.send(info.id, { sdp: pc.localDescription.toJSON(), screen: this.screenStream?.id }))
    }
    this.refreshCount()
    this.announceMedia()
    return peer
  }

  async signal(from, data) {
    if (data.hello) return this.candidate && this.connectTo(from, true)
    const peer = this.connectTo(from, false)
    if (data.screen) peer.screenStreamId = data.screen
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

  // The candidate's shared screen, shown big for the panel.
  showScreen(peer, stream) {
    if (!peer.screenTile) {
      peer.screenTile = document.createElement("div")
      peer.screenTile.className = "it-tile it-screen connected"
      peer.screenTile.innerHTML = `<video autoplay playsinline muted></video><span class="it-name">🖥️ ${esc(peer.name)}'s screen</span>`
      this.gridTarget.prepend(peer.screenTile)
    }
    const video = peer.screenTile.querySelector("video")
    video.srcObject = stream
    video.play().catch(() => {})
  }

  // Proctoring alert from the candidate's browser: banner + beep + red flash on their tile.
  showAlert(alert) {
    warningBeep()
    const item = document.createElement("div")
    item.className = `it-alert sev-${alert.severity}`
    item.innerHTML = `<b>⚠ ${esc(alert.title)}</b>${alert.message ? `<span>${esc(alert.message)}</span>` : ""}${alert.snapshot_url ? `<img src="${esc(alert.snapshot_url)}" alt="">` : ""}`
    this.alertsTarget.prepend(item)
    setTimeout(() => item.remove(), 12000)
    this.gridTarget.querySelectorAll(".role-candidate, .it-screen").forEach((tile) => {
      tile.classList.remove("flagged")
      void tile.offsetWidth
      tile.classList.add("flagged")
    })
  }

  drop(peerId) {
    const peer = this.peers.get(peerId)
    if (!peer) return
    clearTimeout(peer.dropTimer)
    peer.pc.close()
    peer.screenTile?.remove()
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
    if (!this.candidate) this.stream?.getTracks().forEach((t) => t.stop()) // the candidate's camera is shared with proctoring
    this.screenStream?.getTracks().forEach((t) => t.stop())
    this.screenStream = null
    if (redirect && this.leaveUrlValue) window.Turbo.visit(this.leaveUrlValue)
  }

  setStatus(text) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = text
      this.statusTarget.classList.toggle("hidden", !text)
    }
  }
}
