import { Controller } from "@hotwired/stimulus"

// Test language (English / Hindi). HR can switch it while the test runs: the server replaces this
// element and the question paper flips to the other language without reloading (answers are kept).
export default class extends Controller {
  static values = { lang: String }

  connect() {
    document.querySelectorAll("[data-exam-lang]").forEach((el) => { el.dataset.examLang = this.langValue })
  }
}
