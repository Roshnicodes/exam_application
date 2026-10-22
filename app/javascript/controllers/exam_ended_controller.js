import { Controller } from "@hotwired/stimulus"

// HR removed the candidate from the test: end it on their screen right away (answers are already saved).
export default class extends Controller {
  static values = { url: String }

  connect() {
    const exam = document.querySelector('[data-controller~="exam"]')
    if (!exam) return window.location.replace(this.urlValue)
    exam.dispatchEvent(new CustomEvent("proctor:terminated", { detail: { redirect: this.urlValue, reason: "removed" } }))
  }
}
