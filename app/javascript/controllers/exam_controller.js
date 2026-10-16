import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"

// Question navigation, answer autosave, countdown and submission.
export default class extends Controller {
  static targets = [ "form", "question", "navButton", "timer", "clock", "answeredLabel", "confirm", "confirmAnswered", "submitting", "submittingTitle" ]
  static values = { secondsLeft: Number, answerUrl: String }

  connect() {
    this.index = 0
    this.deadline = Date.now() + this.secondsLeftValue * 1000
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
    this.show(0)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  // ---- navigation
  show(i) {
    this.index = Math.max(0, Math.min(i, this.questionTargets.length - 1))
    this.questionTargets.forEach((q, n) => q.classList.toggle("hidden", n !== this.index))
    this.navButtonTargets.forEach((b, n) => b.classList.toggle("current", n === this.index))
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  next() { this.show(this.index + 1) }
  prev() { this.show(this.index - 1) }
  goto(e) { this.show(Number(e.currentTarget.dataset.index)) }

  flag() {
    this.navButtonTargets[this.index].classList.toggle("flagged")
  }

  clear() {
    const q = this.questionTargets[this.index]
    q.querySelectorAll("input[type=radio]").forEach((r) => (r.checked = false))
    this.save(q.dataset.questionId, "")
    this.navButtonTargets[this.index].classList.remove("answered")
    this.updateCount()
  }

  // ---- answers
  answer(e) {
    const q = e.target.closest("[data-question-id]")
    this.navButtonTargets[this.questionTargets.indexOf(q)].classList.add("answered")
    this.save(q.dataset.questionId, e.target.value)
    this.updateCount()
  }

  async save(questionId, option) {
    try {
      const res = await fetch(this.answerUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ question_id: questionId, option })
      })
      const data = await res.json()
      if (data.terminated && data.redirect) window.location.replace(data.redirect)
      if (typeof data.seconds_left === "number") this.deadline = Date.now() + data.seconds_left * 1000
    } catch (e) {
      console.warn("Autosave failed; the answer will still be sent on submit", e)
    }
  }

  answeredCount() {
    return this.questionTargets.filter((q) => q.querySelector("input:checked")).length
  }

  updateCount() {
    if (this.hasAnsweredLabelTarget) this.answeredLabelTarget.textContent = this.answeredCount()
  }

  // ---- timer
  tick() {
    const left = Math.max(0, Math.round((this.deadline - Date.now()) / 1000))
    const m = String(Math.floor(left / 60)).padStart(2, "0")
    const s = String(left % 60).padStart(2, "0")
    this.clockTarget.textContent = `${m}:${s}`
    this.timerTarget.classList.toggle("low", left <= 60)
    if (left === 0) {
      clearInterval(this.timer)
      this.submit("Time is up! Submitting…")
    }
  }

  // ---- submission
  confirmSubmit() {
    this.confirmAnsweredTarget.textContent = this.answeredCount()
    this.confirmTarget.classList.remove("hidden")
  }

  cancelSubmit() {
    this.confirmTarget.classList.add("hidden")
  }

  async submit(title) {
    if (this.submitted) return
    this.submitted = true
    this.confirmTarget.classList.add("hidden")
    if (typeof title === "string") this.submittingTitleTarget.textContent = title
    this.submittingTarget.classList.remove("hidden")

    const waits = []
    this.dispatch("before-submit", { detail: { waits } })
    await Promise.race([ Promise.allSettled(waits), new Promise((r) => setTimeout(r, 20000)) ])
    this.formTarget.submit()
  }

  // Server ended the exam (warning limit). Answers were already autosaved.
  async forceSubmit(event) {
    if (this.submitted) return
    this.submitted = true
    clearInterval(this.timer)
    this.submittingTitleTarget.textContent = "Exam terminated"
    this.submittingTarget.classList.remove("hidden")
    const waits = []
    this.dispatch("before-submit", { detail: { waits } })
    await Promise.race([ Promise.allSettled(waits), new Promise((r) => setTimeout(r, 15000)) ])
    window.location.replace(event.detail.redirect)
  }
}
