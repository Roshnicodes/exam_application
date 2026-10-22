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
      const ok = await translatePaper(true, (text) => this.busy(text))
      this.busy(null)
      if (!ok) {
        window.alert("Hindi isn't available in this browser. Please use the latest Google Chrome on a computer, or ask HR for the Hindi paper.\n\nइस ब्राउज़र में हिंदी उपलब्ध नहीं है। कंप्यूटर पर नया Google Chrome इस्तेमाल करें या HR से हिंदी पेपर माँगें।")
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
    translator = await hindiTranslator((pct) => onBusy?.(`हिंदी ${pct}%`))
  } catch { return false }
  const pending = untranslated()
  for (const [ i, el ] of pending.entries()) {
    if (!el.classList.contains("no-hi") || el.nextElementSibling?.classList.contains("q-hi")) { el.classList.remove("no-hi"); continue }
    onBusy?.(`हिंदी ${Math.round((i / pending.length) * 100)}%`)
    const copy = await translateElement(translator, el)
    copy.classList.remove("q-en", "no-hi")
    copy.classList.add("q-hi")
    el.after(copy)
    el.classList.remove("no-hi")
  }
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
