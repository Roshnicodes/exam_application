// One-way live camera over WebRTC: the candidate's browser sends its camera to every
// viewer (HR / panelist) directly; Action Cable (LiveVideoChannel) only relays set-up messages.
import { cable } from "@hotwired/turbo-rails"

export const ICE_SERVERS = [ { urls: [ "stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478" ] } ]
const VIDEO_BITRATE = 400_000 // keeps the candidate's upload light even with several viewers

// Candidate side: answers every viewer that joins with an offer carrying the camera + mic.
export class Broadcaster {
  constructor(token) {
    this.token = token
    this.peers = new Map() // viewer_id -> { pc, pending: [] }
  }

  async start(stream) {
    this.stream = stream
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

  received(message) {
    if (message.type === "viewer-joined") this.offer(message.viewer_id)
    else if (message.type === "viewer-left") this.close(message.viewer_id)
    else if (message.type === "signal") this.signal(message.viewer_id, message.data)
  }

  async offer(viewerId) {
    if (!this.stream) return
    this.close(viewerId)
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
    const peer = { pc, pending: [] }
    this.peers.set(viewerId, peer)
    this.stream.getTracks().forEach((track) => pc.addTrack(track, this.stream))
    pc.onicecandidate = (e) => e.candidate && this.send(viewerId, { candidate: e.candidate.toJSON() })
    pc.onconnectionstatechange = () => { if ([ "failed", "closed" ].includes(pc.connectionState)) this.close(viewerId) }

    await pc.setLocalDescription(await pc.createOffer())
    this.limitBitrate(pc)
    this.send(viewerId, { sdp: pc.localDescription.toJSON() })
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
    this.peers.forEach((_, id) => this.close(id))
    this.subscription?.unsubscribe()
    this.subscription = null
  }
}

export function newViewerId() {
  return window.crypto?.randomUUID?.() || `v-${Date.now()}-${Math.random().toString(36).slice(2)}`
}
