import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"

// The candidate chooses English or Hindi: the paper flips right away (answers are kept) and the
// choice is saved, so it stays after a reload and HR sees it.
export default class extends Controller {
  static values = { url: String }

  async choose(event) {
    const lang = event.currentTarget.dataset.lang
    showLanguage(lang)
    try {
      await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "X-CSRF-Token": csrfToken(), "Content-Type": "application/json" },
        body: JSON.stringify({ language: lang })
      })
    } catch {}
  }
}

export function showLanguage(lang) {
  document.querySelectorAll("[data-exam-lang]").forEach((el) => { el.dataset.examLang = lang })
  document.querySelectorAll(".lang-pick button[data-lang]").forEach((b) => {
    const on = b.dataset.lang === lang
    b.classList.toggle("active", on)
    b.setAttribute("aria-pressed", on)
  })
}
