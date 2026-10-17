import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ICE_SERVERS, newViewerId } from "lib/live_video"
import { getStream, screenShareSupported, getScreenStream, requestScreen } from "lib/media"
import { warningBeep, chime } from "lib/sound"

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

// Meet-style interview room: everyone sees and hears everyone (WebRTC mesh, best for up to ~6 people).
// With test: true it is the video call during the online test: HR / panelists press "Join", the
// candidate's exam page is always waiting in the room and the call pops up as soon as someone joins.
export default class extends Controller {
  static targets = [ "grid", "localVideo", "micBtn", "camBtn", "status", "nameInput", "joinPanel", "room", "count",
                     "screenGate", "screenError", "alerts", "tap", "chat", "chatBtn", "unread", "messages", "chatInput",
                     "presentBtn", "codeBtn", "switchBtn", "switchNote", "code", "codeLang", "codeBy", "codeInput" ]
  static values = { roundId: Number, invitationId: Number, test: Boolean, token: String, watchToken: String, name: String,
                    needsName: Boolean, leaveUrl: String }

  connect() {
    this.peers = new Map() // peerId -> { pc, pending, tile, name, role, screenStreamId, screenTile }
    this.peerId = newViewerId()
    this.unread = 0
    if (this.hasPresentBtnTarget && !navigator.mediaDevices?.getDisplayMedia) this.presentBtnTarget.hidden = true // phones
    if (this.testValue) {
      if (this.candidate) this.join() // waits quietly; the call opens when HR / a panelist joins
      return
    }
    if (this.candidate && this.screenShareSupported) {
      const existing = getScreenStream() // still sharing from the test in this tab
      if (existing) return this.useScreen(existing)
      return this.screenGateTarget.classList.remove("hidden")
    }
    if (!this.needsNameValue) this.join()
  }

  get candidate() {
    return this.hasTokenValue && this.tokenValue !== ""
  }

  // Phones / tablets can't share their screen; desktops must.
  get screenShareSupported() {
    return screenShareSupported()
  }

  // ---- Candidate: share the entire screen before joining -------------------
  async shareScreen() {
    this.screenErrorTarget.textContent = ""
    window.dispatchEvent(new Event("proctor:picking"))
    try {
      await this.useScreen(await requestScreen())
      document.documentElement.requestFullscreen?.({ navigationUI: "hide" }).catch(() => {})
    } catch (e) {
      if (e.name === "NotEntireScreen") {
        this.screenErrorTarget.textContent = e.message
        window.dispatchEvent(new CustomEvent("proctor:violation", { detail: { kind: "screen_not_entire", message: `Picked a ${e.surface}` } }))
      } else {
        this.screenErrorTarget.textContent = "Screen sharing is required to join. Click the button and choose “Entire screen”."
      }
    } finally {
      window.dispatchEvent(new Event("proctor:picked"))
    }
  }

  async useScreen(stream) {
    const track = stream.getVideoTracks()[0]
    track.addEventListener("ended", () => this.screenStopped(), { once: true })
    const first = !this.screenStream
    this.screenStream = stream
    this.screenGateTarget.classList.add("hidden")
    if (first) await this.join()
    else this.peers.forEach((peer) => peer.screenSender?.replaceTrack(track)) // re-shared: swap the track, no reconnect
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
    if (this.hasNameInputTarget) {
      const name = this.nameInputTarget.value.trim()
      if (!name) return this.nameInputTarget.focus()
      try { localStorage.setItem("panelist-name", name) } catch {}
      this.nameValue = name
    }
    this.joinPanelTarget.classList.add("hidden")
    this.join()
  }

  get waitingCandidate() {
    return this.testValue && this.candidate
  }

  async join() {
    if (!this.waitingCandidate) this.roomTarget.classList.remove("hidden")
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
    if (this.testValue) params.test = true
    if (this.tokenValue) params.token = this.tokenValue
    else if (this.testValue) Object.assign(params, { invitation_id: this.invitationIdValue, watch_token: this.watchTokenValue, name: this.nameValue })
    else Object.assign(params, { round_id: this.roundIdValue, watch_token: this.watchTokenValue, name: this.nameValue })

    // start proctoring now that we're in (the online test's proctoring is already running)
    if (this.candidate && !this.testValue) window.dispatchEvent(new Event("interview:ready"))

    this.subscription = await cable.subscribeTo(params, {
      connected: () => this.setStatus(this.testValue ? "Connected — waiting for the candidate (they join automatically while in the test)" : "Connected — waiting for others to join"),
      rejected: () => this.setStatus(this.testValue ? "The call is available while the candidate is taking the test" : "The interview room is not open"),
      received: (m) => this.received(m)
    })
  }

  received(message) {
    if (message.type === "welcome") { this.myKey = message.key; return }
    if (message.type === "allow-switch") return this.switchAllowed(message.on, message.by)
    if (message.type === "code") return this.codeReceived(message)
    if (message.type === "peer-joined" && message.peer.id !== this.peerId && message.peer.key) {
      // the same person joined again (refresh / another tab)
      if (message.peer.key === this.myKey) return this.replacedElsewhere()
      this.peers.forEach((p, id) => { if (p.key === message.peer.key) this.drop(id) })
    }
    if (message.type === "chat-history") return this.showHistory(message.messages)
    if (message.type === "chat") return this.addMessage(message.message, message.from === this.peerId, true)
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
        peer.presenting = message.screen
        this.renderPresentation(peer)
      }
    }
  }

  connectTo(info, initiator) {
    let peer = this.peers.get(info.id)
    if (peer && !initiator) return peer
    if (peer) this.drop(info.id)

    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
    peer = { pc, pending: [], name: info.name, role: info.role, key: info.key, tile: this.addTile(info) }
    this.peers.set(info.id, peer)
    this.stream.getTracks().forEach((t) => pc.addTrack(t, this.stream))
    const screenTrack = this.screenStream?.getVideoTracks()[0]
    if (screenTrack) peer.screenSender = pc.addTrack(screenTrack, this.screenStream)
    if (!this.stream.getAudioTracks().length) pc.addTransceiver("audio", { direction: "recvonly" })
    if (!this.stream.getVideoTracks().length) pc.addTransceiver("video", { direction: "recvonly" })
    // a spare video line either side can "Present" a screen on later, without reconnecting
    if (initiator) {
      peer.slot = pc.addTransceiver("video", { direction: "sendrecv" })
      if (this.presentTrack) peer.slot.sender.replaceTrack(this.presentTrack)
    }

    pc.ontrack = (e) => {
      if (e.transceiver === peer.slot || (peer.slotMid && e.transceiver.mid === peer.slotMid)) {
        peer.presentStream = new MediaStream([ e.track ])
        return this.renderPresentation(peer)
      }
      if (peer.screenStreamId && e.streams[0]?.id === peer.screenStreamId) return this.showScreen(peer, e.streams[0])
      const video = peer.tile.querySelector("video")
      if (video.srcObject !== e.streams[0]) video.srcObject = e.streams[0]
      video.play().catch(() => this.needTap())
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
        .then(() => this.send(info.id, { sdp: pc.localDescription.toJSON(), screen: this.screenStream?.id, slot: peer.slot.mid }))
    }
    this.refreshCount()
    this.announceMedia()
    return peer
  }

  async signal(from, data) {
    if (data.hello) return this.candidate && this.connectTo(from, true)
    const peer = this.connectTo(from, false)
    if (data.screen) peer.screenStreamId = data.screen
    if (data.slot) peer.slotMid = data.slot
    if (data.sdp) {
      await peer.pc.setRemoteDescription(data.sdp)
      for (const c of peer.pending.splice(0)) await peer.pc.addIceCandidate(c).catch(() => {})
      if (data.sdp.type === "offer") {
        const slot = peer.pc.getTransceivers().find((t) => t.mid === peer.slotMid)
        if (slot) {
          slot.direction = "sendrecv"
          peer.slot = slot
          if (this.presentTrack) await slot.sender.replaceTrack(this.presentTrack)
        }
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
    peer.presentTile?.remove()
    peer.tile.remove()
    this.peers.delete(peerId)
    this.refreshCount()
  }

  send(to, data) {
    this.subscription?.perform("signal", { to, data })
  }

  // ---- Chat: the panel types questions, the candidate answers ---------------
  toggleChat(force) {
    const open = typeof force === "boolean" ? force : this.chatTarget.classList.contains("hidden")
    this.chatTarget.classList.toggle("hidden", !open)
    this.chatBtnTarget.classList.toggle("active", open)
    this.element.classList.toggle("chat-open", open)
    if (open) {
      this.setUnread(0)
      this.scrollChat()
      if (typeof force !== "boolean") this.chatInputTarget.focus({ preventScroll: true }) // opened by hand
    }
  }

  chatKey(event) {
    if (event.key === "Enter" && !event.shiftKey) this.sendChat(event)
  }

  sendChat(event) {
    event.preventDefault()
    const body = this.chatInputTarget.value.trim()
    if (!body || !this.subscription) return
    this.subscription.perform("chat", { body })
    this.chatInputTarget.value = ""
  }

  showHistory(messages) {
    this.messagesTarget.querySelectorAll(".it-msg").forEach((li) => li.remove())
    messages.forEach((m) => this.addMessage(m, m.mine, false))
  }

  addMessage(m, mine, live) {
    this.messagesTarget.querySelector(".it-msg-empty")?.remove()
    const li = document.createElement("li")
    li.className = `it-msg role-${m.role} ${mine ? "mine" : ""}`
    const time = new Date(m.at).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
    const role = { candidate: "Candidate", hr: "HR", panelist: "Panelist" }[m.role] || ""
    li.innerHTML = `<div class="it-msg-meta"><b>${esc(mine ? "You" : m.name)}</b><em>${esc(role)}</em><span>${esc(time)}</span></div><p>${esc(m.body)}</p>`
    this.messagesTarget.append(li)
    this.scrollChat()
    if (!live || mine) return
    if (this.candidate) {
      // a question for the candidate: open the call window and the chat so it can't be missed
      this.element.classList.remove("minimized")
      this.toggleChat(true)
      chime()
    } else if (this.chatTarget.classList.contains("hidden")) {
      this.setUnread(this.unread + 1)
      chime()
    }
  }

  setUnread(n) {
    this.unread = n
    this.unreadTarget.textContent = n
    this.unreadTarget.classList.toggle("hidden", n === 0)
  }

  scrollChat() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  // ---- Same person joined from another tab: this copy steps out ------------
  replacedElsewhere() {
    this.leave(false)
    this.roomTarget.classList.remove("hidden")
    this.setStatus("You joined this call from another tab or window, so this one has left. Use the newest one.")
  }

  // ---- Present: share your screen with everyone (panel members) ------------
  async togglePresent() {
    if (this.presentTrack) return this.stopPresent()
    let stream
    try {
      stream = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 10 }, audio: false })
    } catch {
      return
    }
    this.presentTrack = stream.getVideoTracks()[0]
    this.presentTrack.addEventListener("ended", () => this.stopPresent(), { once: true })
    this.peers.forEach((peer) => peer.slot?.sender.replaceTrack(this.presentTrack))
    this.presentBtnTarget.classList.add("active")
    this.presentBtnTarget.querySelector("span").textContent = "Stop presenting"
    this.showOwnPresentation(stream)
    this.announceMedia()
  }

  stopPresent(announce = true) {
    if (!this.presentTrack) return
    this.presentTrack.stop()
    this.presentTrack = null
    this.peers.forEach((peer) => peer.slot?.sender.replaceTrack(null).catch(() => {}))
    if (this.hasPresentBtnTarget) {
      this.presentBtnTarget.classList.remove("active")
      this.presentBtnTarget.querySelector("span").textContent = "Present"
    }
    this.ownPresentTile?.remove()
    this.ownPresentTile = null
    if (announce) this.announceMedia()
  }

  showOwnPresentation(stream) {
    this.ownPresentTile = this.presentationTile("You are presenting")
    this.ownPresentTile.querySelector("video").srcObject = stream
  }

  // Someone else's presented screen: shown big at the top while they present.
  renderPresentation(peer) {
    if (peer.presenting && peer.presentStream) {
      peer.presentTile ||= this.presentationTile(`${peer.name} is presenting`)
      const video = peer.presentTile.querySelector("video")
      if (video.srcObject !== peer.presentStream) video.srcObject = peer.presentStream
      video.play().catch(() => {})
    } else {
      peer.presentTile?.remove()
      peer.presentTile = null
    }
  }

  presentationTile(label) {
    const tile = document.createElement("div")
    tile.className = "it-tile it-screen it-present connected"
    tile.innerHTML = `<video autoplay playsinline muted></video><span class="it-name">🖥️ ${esc(label)}</span>`
    this.gridTarget.prepend(tile)
    return tile
  }

  // ---- Allow switching apps (panel -> candidate) ---------------------------
  toggleSwitch() {
    this.subscription?.perform("allow_switch", { on: !this.switchOn })
  }

  switchAllowed(on, by) {
    this.switchOn = on
    if (this.hasSwitchBtnTarget) {
      this.switchBtnTarget.classList.toggle("active", on)
      this.switchBtnTarget.querySelector("span").textContent = on ? "Switching allowed — turn off" : "Allow switching apps"
    }
    this.switchNoteTarget.classList.toggle("hidden", !on)
    this.switchNoteTarget.textContent = this.candidate
      ? "✅ The panel allowed you to open another app or website (e.g. an online editor). Your screen is still shared with them."
      : `✅ Candidate may switch apps${by ? ` (turned on by ${by})` : ""} — tab-switch and full-screen warnings are paused. Watch their shared screen.`
    if (this.candidate) window.dispatchEvent(new CustomEvent("proctor:allow-switch", { detail: { on } }))
  }

  // ---- Shared code pad ------------------------------------------------------
  toggleCode(force) {
    const open = typeof force === "boolean" ? force : this.codeTarget.classList.contains("hidden")
    this.codeTarget.classList.toggle("hidden", !open)
    this.codeBtnTarget.classList.toggle("active", open)
    if (open && typeof force !== "boolean") {
      this.codeInputTarget.focus({ preventScroll: true })
      if (!this.candidate) this.sendCode() // opens the pad for the candidate too
    }
  }

  codeKey(event) {
    if (event.key !== "Tab") return
    event.preventDefault()
    const el = this.codeInputTarget
    el.setRangeText("  ", el.selectionStart, el.selectionEnd, "end")
    this.codeChanged()
  }

  codeChanged() {
    this.lastCodeEdit = Date.now()
    clearTimeout(this.codeTimer)
    this.codeTimer = setTimeout(() => this.sendCode(), 400)
  }

  sendCode() {
    this.subscription?.perform("code", { content: this.codeInputTarget.value, language: this.codeLangTarget.value })
  }

  codeReceived(m) {
    if (m.from === this.peerId) return
    this.codeLangTarget.value = m.language
    const el = this.codeInputTarget
    // don't overwrite what this person is typing right now
    if (el.value !== m.content && !(document.activeElement === el && Date.now() - (this.lastCodeEdit || 0) < 1500)) {
      const pos = el.selectionStart
      el.value = m.content
      el.selectionStart = el.selectionEnd = Math.min(pos, el.value.length)
    }
    if (m.by) this.codeByTarget.textContent = `Last edit: ${m.by}`
    if (this.codeTarget.classList.contains("hidden") && (m.from || this.candidate)) this.toggleCode(true)
  }

  // Browsers can block sound until the page is clicked; offer a button and retry on the next click / key.
  needTap() {
    if (this.hasTapTarget) this.tapTarget.classList.remove("hidden")
    if (this.tapWaiting) return
    this.tapWaiting = true
    const retry = () => { this.tapWaiting = false; this.playAll() }
    window.addEventListener("pointerdown", retry, { once: true })
    window.addEventListener("keydown", retry, { once: true })
  }

  playAll() {
    this.gridTarget.querySelectorAll("video").forEach((v) => v.play().catch(() => {}))
    if (this.hasTapTarget) this.tapTarget.classList.add("hidden")
  }

  minimize() {
    this.element.classList.toggle("minimized")
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
    this.subscription?.perform("media_state", { mic, cam, screen: !!this.presentTrack })
  }

  updateButtons() {
    if (!this.hasMicBtnTarget) return
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
    if (this.waitingCandidate) {
      // the candidate's call panel opens while someone from the panel is in the call
      const inCall = this.peers.size > 0
      this.roomTarget.classList.toggle("hidden", !inCall)
      if (!inCall) this.element.classList.remove("minimized")
      window.dispatchEvent(new CustomEvent("proctor:call", { detail: { active: inCall } }))
    }
  }

  leave(redirect = true) {
    this.stopPresent(false)
    this.peers.forEach((_, id) => this.drop(id))
    this.subscription?.unsubscribe()
    this.subscription = null
    if (!this.candidate) this.stream?.getTracks().forEach((t) => t.stop()) // the candidate's camera is shared with proctoring
    this.screenStream?.getTracks().forEach((t) => t.stop())
    this.screenStream = null
    if (this.testValue && !this.candidate) {
      // back to the "Join video call" button
      this.stream = null
      this.roomTarget.classList.add("hidden")
      if (this.hasJoinPanelTarget) this.joinPanelTarget.classList.remove("hidden")
      return
    }
    if (redirect && this.leaveUrlValue) window.Turbo.visit(this.leaveUrlValue)
  }

  setStatus(text) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = text
      this.statusTarget.classList.toggle("hidden", !text)
    }
  }
}
