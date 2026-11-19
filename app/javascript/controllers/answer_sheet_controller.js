import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"

// The candidate's answer sheet for a practical test that has an answer key, one question at a time:
// the question and a box to type the answer in. Saves itself; marked on the server when they submit
// (or when the time ends — the assessment controller waits for the last save).
export default class extends Controller {
  static targets = [ "progress", "status", "item", "navButton", "prev", "next", "finish" ]
  static values = { url: String, total: Number, key: String }

  connect() {
    this.index = 0
    try { this.index = Math.min(Number(sessionStorage.getItem(this.keyValue)) || 0, this.itemTargets.length - 1) } catch {}
    this.show(this.index, false)
    this.refresh()
    this.submitHook = (e) => { this.fillForm(); e.detail?.waits?.push(this.save()) }
    this.assessment = this.element.closest("[data-controller~='assessment']")
    this.assessment?.addEventListener("assessment:before-submit", this.submitHook)
    this.timer = setInterval(() => { if (this.dirty) this.save() }, 20000)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.debounce)
    this.assessment?.removeEventListener("assessment:before-submit", this.submitHook)
  }

  // ---------------------------------------------------------------- moving between questions
  go(event) {
    this.show(Number(event.currentTarget.dataset.index))
  }

  next() {
    if (this.index < this.itemTargets.length - 1) this.show(this.index + 1)
  }

  prev() {
    if (this.index > 0) this.show(this.index - 1)
  }

  show(index, scroll = true) {
    this.index = index
    this.itemTargets.forEach((item, i) => { item.hidden = i !== index })
    this.navButtonTargets.forEach((button) => button.classList.toggle("current", Number(button.dataset.index) === index))
    const last = index === this.itemTargets.length - 1
    if (this.hasPrevTarget) this.prevTarget.disabled = index === 0
    if (this.hasNextTarget) this.nextTarget.hidden = last
    if (this.hasFinishTarget) this.finishTarget.hidden = !last
    try { sessionStorage.setItem(this.keyValue, String(index)) } catch {}

    const item = this.itemTargets[index]
    if (!item) return
    window.dispatchEvent(new CustomEvent("answer-sheet:step", { detail: { q: item.dataset.q } }))
    if (scroll) {
      this.navButtonTargets.find((b) => Number(b.dataset.index) === index)?.scrollIntoView({ block: "nearest", inline: "center" })
      const top = this.element.getBoundingClientRect().top
      if (top < 0) this.element.scrollIntoView({ block: "start", behavior: "smooth" })
      item.querySelector("textarea, input[type=text]")?.focus({ preventScroll: true })
    }
  }

  // ---------------------------------------------------------------- answers
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
    const isDone = (id) => String(answers[id] ?? "").trim() !== ""
    const done = Object.keys(answers).filter(isDone).length
    if (this.hasProgressTarget) this.progressTarget.textContent = `${done} / ${this.totalValue} answered`
    this.itemTargets.forEach((item) => item.classList.toggle("done", isDone(item.dataset.id)))
    this.navButtonTargets.forEach((button) => button.classList.toggle("done", isDone(button.dataset.id)))

    // the "Submit your work?" box says what is still unanswered
    const summary = document.getElementById("as-confirm-summary")
    if (summary) {
      const left = this.navButtonTargets.filter((b) => !isDone(b.dataset.id)).map((b) => b.title)
      summary.textContent = left.length
        ? `${done} of ${this.totalValue} answered. Not answered yet: ${left.slice(0, 12).join(", ")}${left.length > 12 ? "…" : ""}`
        : `All ${this.totalValue} questions answered.`
      summary.classList.toggle("as-left", left.length > 0)
    }
  }

  // the answers also go with the submit itself, so nothing is lost if the last autosave fails
  fillForm() {
    const form = this.assessment?.querySelector("[data-assessment-target~='form']")
    if (!form) return
    form.querySelectorAll("input[data-sheet-answer]").forEach((el) => el.remove())
    Object.entries(this.answers()).forEach(([ id, value ]) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = `answers[${id}]`
      input.value = value
      input.dataset.sheetAnswer = ""
      form.append(input)
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
