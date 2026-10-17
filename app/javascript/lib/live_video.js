// One-way live camera over WebRTC: the candidate's browser sends its camera to every
// viewer (HR / panelist) directly; Action Cable (LiveVideoChannel) only relays set-up messages.
import { cable } from "@hotwired/turbo-rails"

// STUN + (when configured on the server) our TURN relay, from <meta name="ice-servers">.
// TURN lets video through networks that block direct connections (mobile data, offices).
export const ICE_SERVERS = (() => {
  try {
    const list = JSON.parse(document.querySelector("meta[name='ice-servers']")?.content || "[]")
    if (list.length) return list
  } catch {}
  return [ { urls: [ "stun:stun.l.google.com:19302", "stun:stun.cloudflare.com:3478" ] } ]
})()
const VIDEO_BITRATE = 400_000 // keeps the candidate's upload light even with several viewers

// Candidate side: answers every viewer that joins with an offer carrying the camera + mic.
export class Broadcaster {
  constructor(token) {
    this.token = token
    this.peers = new Map() // viewer_id -> { pc, pending: [] }
    this.frameViewers = new Set() // viewers on the backup (frames) view
  }

  async start(stream, screen = null) {
    this.stream = stream
    this.screen = screen
    this.subscription = await cable.subscribeTo(
      { channel: "LiveVideoChannel", role: "candidate", token: this.token },
      { received: (message) => this.received(message) }
    )
  }

  // Camera was re-acquired (e.g. after being blocked): swap tracks without reconnecting.
  setStream(stream) {
    this.stream = stream
    this.peers.forEach(({ pc }) => pc.getSenders().forEach((sender) => {
      const track = stream.getTracks().find((t) => t.kind === sender.track?.kind)
      if (track) sender.replaceTrack(track)
    }))
  }

  // The candidate (re)shared their screen: reconnect viewers so they receive it too.
  setScreen(screen) {
    this.screen = screen
    this.peers.forEach((_, id) => this.offer(id))
  }

  received(message) {
    if (message.type === "viewer-joined") this.offer(message.viewer_id)
    else if (message.type === "viewer-left") { this.close(message.viewer_id); this.stopFramesFor(message.viewer_id) }
    else if (message.type === "signal") this.signal(message.viewer_id, message.data)
    else if (message.type === "frames-on") this.startFramesFor(message.viewer_id)
  }

  // ---- backup view: ~1 JPEG per second while someone can't get direct video ----
  startFramesFor(viewerId) {
    this.frameViewers.add(viewerId)
    if (this.frameTimer) return
    this.frameVideo = document.createElement("video")
    this.frameVideo.muted = true
    this.frameVideo.playsInline = true
    this.frameVideo.srcObject = this.stream
    this.frameVideo.play().catch(() => {})
    this.frameCanvas = document.createElement("canvas")
    this.frameTimer = setInterval(() => this.sendFrame(), 1000)
  }

  stopFramesFor(viewerId) {
    this.frameViewers.delete(viewerId)
    if (this.frameViewers.size === 0 && this.frameTimer) {
      clearInterval(this.frameTimer)
      this.frameTimer = null
    }
  }

  sendFrame() {
    const v = this.frameVideo
    if (!v || v.readyState < 2 || !this.subscription) return
    const w = 320
    const h = Math.round(w * (v.videoHeight / v.videoWidth || 0.75))
    this.frameCanvas.width = w
    this.frameCanvas.height = h
    this.frameCanvas.getContext("2d").drawImage(v, 0, 0, w, h)
    this.subscription.perform("frame", { image: this.frameCanvas.toDataURL("image/jpeg", 0.55) })
  }

  async offer(viewerId) {
    if (!this.stream) return
    this.close(viewerId)
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
    const peer = { pc, pending: [] }
    this.peers.set(viewerId, peer)
    this.stream.getTracks().forEach((track) => pc.addTrack(track, this.stream))
    const screenTrack = this.screen?.getVideoTracks().find((t) => t.readyState === "live")
    if (screenTrack) pc.addTrack(screenTrack, this.screen)
    pc.onicecandidate = (e) => e.candidate && this.send(viewerId, { candidate: e.candidate.toJSON() })
    pc.onconnectionstatechange = () => { if ([ "failed", "closed" ].includes(pc.connectionState)) this.close(viewerId) }

    await pc.setLocalDescription(await pc.createOffer())
    this.limitBitrate(pc)
    this.send(viewerId, { sdp: pc.localDescription.toJSON(), screen: screenTrack ? this.screen.id : null })
  }

  async signal(viewerId, data) {
    const peer = this.peers.get(viewerId)
    if (!peer || !data) return
    if (data.sdp) {
      await peer.pc.setRemoteDescription(data.sdp)
      for (const c of peer.pending.splice(0)) await peer.pc.addIceCandidate(c).catch(() => {})
    } else if (data.candidate) {
      if (peer.pc.remoteDescription) await peer.pc.addIceCandidate(data.candidate).catch(() => {})
      else peer.pending.push(data.candidate)
    }
  }

  limitBitrate(pc) {
    pc.getSenders().forEach((sender) => {
      if (sender.track?.kind !== "video") return
      const params = sender.getParameters()
      params.encodings = params.encodings?.length ? params.encodings : [ {} ]
      params.encodings[0].maxBitrate = VIDEO_BITRATE
      sender.setParameters(params).catch(() => {})
    })
  }

  send(to, data) {
    this.subscription?.perform("signal", { to, data })
  }

  close(viewerId) {
    this.peers.get(viewerId)?.pc.close()
    this.peers.delete(viewerId)
  }

  stop() {
    clearInterval(this.frameTimer)
    this.frameTimer = null
    this.peers.forEach((_, id) => this.close(id))
    this.subscription?.unsubscribe()
    this.subscription = null
  }
}

export function newViewerId() {
  return window.crypto?.randomUUID?.() || `v-${Date.now()}-${Math.random().toString(36).slice(2)}`
}
