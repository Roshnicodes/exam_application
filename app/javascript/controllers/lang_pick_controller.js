import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"
import { hindiSupported, hindiTranslator, hindiReady, translateElement } from "lib/hindi"

// The candidate chooses English or Hindi: the paper flips right away (answers are kept) and the
// choice is saved, so it stays after a reload and HR sees it. Questions HR hasn't put in Hindi are
// translated in the browser (Chrome's built-in translator — free, no setup).
export default class extends Controller {
  static values = { url: String }
  static targets = [ "hiBtn", "note" ]

  connect() {
    if (this.hasHiBtnTarget && this.hiBtnTarget.disabled && hindiSupported()) {
      this.hiBtnTarget.disabled = false
      this.hiBtnTarget.removeAttribute("title")
      if (this.hasNoteTarget) this.noteTarget.hidden = true
    }
  }

  async choose(event) {
    const lang = event.currentTarget.dataset.lang
    if (lang === "hi" && untranslated().length) {
      showLanguage("hi") // flips now; each question turns Hindi as soon as it is translated
      const ok = await translatePaper(true, (text) => this.busy(text))
      this.busy(null)
      if (!ok) {
        showLanguage("en")
        window.alert("Couldn't translate to Hindi — please check the internet and try again, or ask HR for the Hindi paper.\n\nहिंदी में नहीं बदल पाए — इंटरनेट चेक करके फिर से कोशिश करें या HR से हिंदी पेपर माँगें।")
        return
      }
    }
    showLanguage(lang)
    try {
      await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "X-CSRF-Token": csrfToken(), "Content-Type": "application/json" },
        body: JSON.stringify({ language: lang })
      })
    } catch {}
  }

  busy(text) {
    if (!this.hasHiBtnTarget) return
    this.hiBtnTarget.textContent = text || "हिंदी"
    this.hiBtnTarget.classList.toggle("busy", !!text)
  }
}

function untranslated() {
  return [ ...document.querySelectorAll(".q-en.no-hi") ]
}

// Puts a Hindi copy next to every question HR didn't translate. `fromClick` may download the
// Hindi pack (Chrome needs a click for that); otherwise it only runs when the pack is already there.
// Only one run at a time — two at once (page load + a click) used to add the Hindi twice.
let running = null

export async function translatePaper(fromClick = false, onBusy = null) {
  while (running) await running.catch(() => {})
  if (!untranslated().length) return true
  running = runTranslation(fromClick, onBusy)
  try { return await running } finally { running = null }
}

async function runTranslation(fromClick, onBusy) {
  if (!fromClick && !(await hindiReady())) return false
  let translator
  try {
    onBusy?.("हिंदी…")
    translator = await hindiTranslator((pct) => onBusy?.(`हिंदी ${pct}%`), fromClick)
  } catch { return false }
  const pending = untranslated()
  let done = 0
  const one = async (el) => {
    if (!el.classList.contains("no-hi") || el.nextElementSibling?.classList.contains("q-hi")) return el.classList.remove("no-hi")
    const copy = await translateElement(translator, el)
    copy.classList.remove("q-en", "no-hi")
    copy.classList.add("q-hi")
    el.after(copy)
    el.classList.remove("no-hi")
    onBusy?.(`हिंदी ${Math.round((++done / pending.length) * 100)}%`)
  }
  // the question on screen first, then the rest a few at a time
  const current = pending.filter((el) => el.offsetParent)
  const rest = pending.filter((el) => !el.offsetParent)
  await Promise.all(current.map(one))
  for (let i = 0; i < rest.length; i += 6) await Promise.all(rest.slice(i, i + 6).map(one))
  return true
}

export function hasUntranslated() {
  return untranslated().length > 0
}

export function showLanguage(lang) {
  document.querySelectorAll("[data-exam-lang]").forEach((el) => { el.dataset.examLang = lang })
  document.querySelectorAll(".lang-pick button[data-lang]").forEach((b) => {
    const on = b.dataset.lang === lang
    b.classList.toggle("active", on)
    b.setAttribute("aria-pressed", on)
  })
}
