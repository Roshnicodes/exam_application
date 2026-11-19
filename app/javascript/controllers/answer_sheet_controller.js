import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"

// The candidate's answer sheet for a practical test that has an answer key: options for MCQs,
// boxes for numbers and written answers. Saves itself; marked on the server when they submit.
export default class extends Controller {
  static targets = [ "progress", "status", "item" ]
  static values = { url: String, total: Number }

  connect() {
    this.refresh()
    this.submitHook = (e) => e.detail?.waits?.push(this.save())
    this.element.closest("[data-controller~='assessment']")?.addEventListener("assessment:before-submit", this.submitHook)
    this.timer = setInterval(() => { if (this.dirty) this.save() }, 20000)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.debounce)
    this.element.closest("[data-controller~='assessment']")?.removeEventListener("assessment:before-submit", this.submitHook)
  }

  changed() {
    this.dirty = true
    this.refresh()
    this.setStatus("Saving…")
    clearTimeout(this.debounce)
    this.debounce = setTimeout(() => this.save(), 1200)
  }

  answers() {
    const out = {}
    this.element.querySelectorAll("[data-answer]").forEach((el) => {
      const id = el.dataset.answer
      if (el.type === "radio") { if (el.checked) out[id] = el.value; else out[id] ??= "" }
      else out[id] = el.value
    })
    return out
  }

  refresh() {
    const answers = this.answers()
    const done = Object.values(answers).filter((v) => String(v).trim() !== "").length
    if (this.hasProgressTarget) this.progressTarget.textContent = `${done} / ${this.totalValue} answered`
    this.itemTargets.forEach((item) => {
      item.classList.toggle("done", String(answers[item.dataset.id] ?? "").trim() !== "")
    })
  }

  async save() {
    clearTimeout(this.debounce)
    if (!this.dirty) return
    this.dirty = false
    try {
      const res = await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ answers: this.answers() })
      })
      if (!res.ok) throw new Error(res.status)
      this.setStatus(`Saved · ${new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`)
    } catch {
      this.dirty = true
      this.setStatus("Not saved — retrying…", true)
      this.debounce = setTimeout(() => this.save(), 5000)
    }
  }

  setStatus(text, bad = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("bad", bad)
  }
}
