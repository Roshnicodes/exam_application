import { Controller } from "@hotwired/stimulus"
import { showLanguage, translatePaper, hasUntranslated } from "controllers/lang_pick_controller"
import { hindiSupported } from "lib/hindi"

// Test language (English / Hindi). HR can switch it while the test runs: the server replaces this
// element and the question paper flips to the other language without reloading (answers are kept).
export default class extends Controller {
  static values = { lang: String }

  async connect() {
    showLanguage(this.langValue)
    removePrompt()
    if (this.langValue !== "hi" || !hasUntranslated()) return
    // questions without HR's Hindi: translate now if Chrome already has the Hindi pack,
    // otherwise ask for one click (Chrome only downloads it after a click)
    if (!(await translatePaper(false)) && hindiSupported()) showPrompt()
  }
}

function removePrompt() {
  document.getElementById("hi-prompt")?.remove()
}

function showPrompt() {
  removePrompt()
  const bar = document.createElement("div")
  bar.id = "hi-prompt"
  bar.className = "hi-prompt"
  bar.innerHTML = `<span>पेपर हिंदी में चुना गया है · The paper is set to Hindi</span><button type="button">हिंदी में देखें · Show in Hindi</button>`
  const button = bar.querySelector("button")
  button.addEventListener("click", async () => {
    button.disabled = true
    const ok = await translatePaper(true, (text) => { button.textContent = text })
    if (ok) { showLanguage("hi"); bar.remove() } else {
      bar.querySelector("span").textContent = "Couldn't translate to Hindi — check the internet and try again. · हिंदी में नहीं बदल पाए — इंटरनेट चेक करें।"
      button.remove()
    }
  })
  document.querySelector(".exam-layout")?.before(bar)
}
