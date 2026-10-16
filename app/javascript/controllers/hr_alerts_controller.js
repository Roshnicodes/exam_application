import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { phoneRing, siren, chime, unlockAudio } from "lib/sound"

const ICONS = {
  alert: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4M12 17h.01"/>',
  key: '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/>',
  check: '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
  play: '<path d="m6 3 14 9-14 9z"/>',
  bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
  volOn: '<path d="M11 5 6 9H2v6h4l5 4zM15.54 8.46a5 5 0 0 1 0 7.07M19.07 4.93a10 10 0 0 1 0 14.14"/>',
  volOff: '<path d="M11 5 6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6"/>'
}
const svg = (name) => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name]}</svg>`
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

// Lives in a data-turbo-permanent element so the websocket, audio context and
// sound preference survive Turbo page visits. Rings + notifies HR on candidate activity.
export default class extends Controller {
  connect() {
    this.soundOn = this.readPref()
    this.subscription = cable.subscribeTo("HrAlertsChannel", {
      received: (data) => this.received(data),
      connected: () => this.setLive(true),
      disconnected: () => this.setLive(false)
    })
    this.onClick = (e) => { if (e.target.closest("#sound-toggle")) this.toggleSound() }
    this.onLoad = () => { this.renderToggle(); this.setLive(this.live) }
    this.unlockOnce = () => { if (this.soundOn) unlockAudio() }
    document.addEventListener("click", this.onClick)
    document.addEventListener("turbo:load", this.onLoad)
    document.addEventListener("pointerdown", this.unlockOnce, { once: true })
    this.renderToggle()
  }

  disconnect() {
    this.subscription?.then?.((s) => s.unsubscribe())
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("turbo:load", this.onLoad)
  }

  async toggleSound() {
    this.soundOn = !this.soundOn
    try { localStorage.setItem("hr-sound", this.soundOn ? "1" : "0") } catch {}
    if (this.soundOn) {
      await unlockAudio()
      chime()
      if ("Notification" in window && Notification.permission === "default") Notification.requestPermission()
    }
    this.renderToggle()
  }

  readPref() {
    try { return localStorage.getItem("hr-sound") === "1" } catch { return false }
  }

  renderToggle() {
    const btn = document.getElementById("sound-toggle")
    if (!btn) return
    btn.classList.toggle("on", this.soundOn)
    btn.innerHTML = `${svg(this.soundOn ? "volOn" : "volOff")}<span>${this.soundOn ? "Sound alerts on" : "Enable sound alerts"}</span>`
  }

  setLive(live) {
    this.live = live
    document.getElementById("live-indicator")?.classList.toggle("off", !live)
    const label = document.getElementById("live-label")
    if (label) label.textContent = live ? "Live monitoring active" : "Reconnecting to live alerts…"
  }

  received(data) {
    const critical = [ "critical", "high" ].includes(data.severity)
    if (this.soundOn) {
      if (data.kind === "otp_requested") phoneRing({ times: 2 })
      else if (data.severity === "critical" || data.kind === "exam_terminated") siren()
      else if (critical || data.severity === "medium") phoneRing({ times: 1 })
      else chime()
    }

    if (data.kind === "otp_requested") this.showOtp(data)
    else this.toast(data)

    this.browserNotify(data)
    this.prependFeed(data)
    this.flashTile(data)
    this.bumpTitle()
  }

  // One popup that collects every pending OTP, newest on top, so a whole batch can be read out.
  showOtp(data) {
    let el = document.getElementById("otp-modal")
    if (!el) {
      el = document.createElement("div")
      el.id = "otp-modal"
      el.className = "modal-backdrop"
      el.innerHTML = `
        <div class="modal otp-modal">
          <div class="modal-top">
            <div class="ring-ico">${svg("key")}</div>
            <h2>OTP requests</h2>
            <p>Read the code out to each candidate</p>
          </div>
          <div class="otp-list"></div>
          <div class="row" style="padding:1rem 1.2rem 1.2rem">
            <button type="button" class="btn btn-light grow" data-close>Close all</button>
          </div>
        </div>`
      el.addEventListener("click", (e) => {
        if (e.target === el || e.target.closest("[data-close]")) el.remove()
        const done = e.target.closest("[data-done]")
        if (done) {
          done.closest(".otp-item").remove()
          if (!el.querySelector(".otp-item")) el.remove()
        }
      })
      document.body.appendChild(el)
    }
    const list = el.querySelector(".otp-list")
    list.querySelector(`[data-invitation="${data.invitation_id}"]`)?.remove() // a resend replaces the old code
    list.insertAdjacentHTML("afterbegin", `
      <div class="otp-item" data-invitation="${esc(data.invitation_id)}">
        <div class="grow" style="min-width:0">
          <b>${esc(data.candidate)}</b>
          <small>${esc(data.vacancy)} · ${esc(data.message?.split(" - ")[0] || "")}</small>
        </div>
        <span class="otp-code">${esc(data.otp)}</span>
        <a href="${esc(data.url)}" class="act-btn" title="Open candidate" data-close>${svg("play")}</a>
        <button type="button" class="act-btn" title="Done" data-done>${'<svg class="icon" viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></svg>'}</button>
      </div>`)
    el.querySelector("h2").textContent = `OTP requests (${list.children.length})`
  }

  toast(data) {
    const stack = document.getElementById("flash-stack")
    if (!stack) return
    const tone = { critical: "danger", high: "danger", medium: "warn", low: "warn" }[data.severity] || "info"
    const ico = { exam_started: "play", exam_submitted: "check", verified: "check" }[data.kind] || (tone === "info" ? "bell" : "alert")
    const el = document.createElement("div")
    el.className = `toast ${tone}`
    el.innerHTML = `
      <span class="ico ${tone === "danger" ? "ring-shake" : ""}">${svg(ico)}</span>
      <div class="grow">
        <b>${esc(data.title)}</b>
        <p>${esc(data.candidate)} · ${esc(data.vacancy)}${data.message ? ` — ${esc(data.message)}` : ""}</p>
        ${data.max_warnings && [ "danger", "warn" ].includes(tone) ? `<p><b style="color:var(--red)">Warning ${data.warnings}${data.max_warnings ? "/" + data.max_warnings : ""}</b></p>` : ""}
        ${data.snapshot_url ? `<img src="${esc(data.snapshot_url)}" alt="snapshot">` : ""}
        <a href="${esc(data.url)}" class="small" style="font-weight:700">View live →</a>
      </div>
      <button class="close" aria-label="Close">${'<svg class="icon" viewBox="0 0 24 24"><path d="M18 6 6 18M6 6l12 12"/></svg>'}</button>`
    const remove = () => { el.classList.add("leaving"); setTimeout(() => el.remove(), 300) }
    el.querySelector(".close").addEventListener("click", remove)
    stack.prepend(el)
    setTimeout(remove, tone === "danger" ? 12000 : 7000)
    while (stack.children.length > 5) stack.lastElementChild.remove()
  }

  browserNotify(data) {
    if (!("Notification" in window) || Notification.permission !== "granted") return
    if (document.visibilityState === "visible" && document.hasFocus()) return
    const body = data.kind === "otp_requested"
      ? `OTP: ${data.otp} — share with ${data.candidate}`
      : `${data.candidate} (${data.vacancy})${data.message ? " — " + data.message : ""}`
    const n = new Notification(`${data.kind === "otp_requested" ? "🔑" : "⚠️"} ${data.title}`, {
      body, tag: `exam-${data.invitation_id}-${data.kind}`, renotify: true, requireInteraction: data.kind === "otp_requested",
      icon: data.snapshot_url || document.querySelector("link[rel=icon][type='image/png']")?.href
    })
    n.onclick = () => { window.focus(); window.Turbo?.visit(data.url); n.close() }
  }

  // Live monitor: make the candidate's tile blink red on suspicious activity.
  flashTile(data) {
    if (![ "critical", "high", "medium", "low" ].includes(data.severity)) return
    const tile = document.getElementById(`mon_wrap_${data.invitation_id}`)
    if (!tile) return
    tile.classList.remove("alerting")
    void tile.offsetWidth // restart the animation
    tile.classList.add("alerting")
    setTimeout(() => tile.classList.remove("alerting"), 6000)
  }

  prependFeed(data) {
    const feed = document.getElementById("dashboard-feed")
    if (!feed) return
    document.getElementById("feed-empty")?.remove()
    const sev = data.severity || "info"
    const li = document.createElement("li")
    li.className = "flash-new"
    li.innerHTML = `
      <span class="t-ico sev-${esc(sev)}">${svg([ "critical", "high", "medium", "low" ].includes(sev) ? "alert" : "bell")}</span>
      <div class="t-body">
        <div class="row between" style="gap:.5rem"><b>${esc(data.title)}</b><span class="tiny muted">${new Date(data.at).toLocaleTimeString()}</span></div>
        <p><a href="${esc(data.url)}">${esc(data.candidate)}</a> · ${esc(data.vacancy)}</p>
      </div>
      ${data.snapshot_url ? `<img class="t-snap" src="${esc(data.snapshot_url)}" alt="">` : ""}`
    feed.prepend(li)
  }

  bumpTitle() {
    if (document.hasFocus()) return
    const base = document.title.replace(/^\(\d+\) /, "")
    this.unread = (this.unread || 0) + 1
    document.title = `(${this.unread}) ${base}`
    window.addEventListener("focus", () => { this.unread = 0; document.title = base }, { once: true })
  }
}
