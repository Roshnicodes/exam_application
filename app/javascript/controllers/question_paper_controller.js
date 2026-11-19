import { Controller } from "@hotwired/stimulus"

// The question paper shown next to the answer sheet. Loads the paper inside the page (never a new
// tab, so reading it is not a tab switch), follows the question the candidate is on, and lets them
// make the text bigger.
export default class extends Controller {
  static targets = [ "body" ]
  static values = { kind: String, src: String }

  connect() {
    this.scale = 1
    this.load()
  }

  async load() {
    const body = this.bodyTarget
    if (this.kindValue === "doc" || this.kindValue === "sheet") {
      try {
        const response = await fetch(this.srcValue, { headers: { Accept: "text/html" } })
        if (!response.ok) throw new Error(await response.text())
        body.innerHTML = await response.text()
        if (this.pending) this.highlight(this.pending)
      } catch (e) {
        body.replaceChildren(this.message("The paper could not be shown here — use “Full paper”, or ask HR in the chat."))
      }
    } else if (this.kindValue === "pdf" || this.kindValue === "text") {
      const frame = document.createElement("iframe")
      frame.src = this.srcValue
      frame.title = "Question paper"
      body.replaceChildren(frame)
    } else if (this.kindValue === "image") {
      const img = document.createElement("img")
      img.src = this.srcValue
      img.alt = "Question paper"
      body.replaceChildren(img)
    } else {
      body.replaceChildren(this.message("This paper can't be shown inside the page."))
    }
  }

  // the answer sheet moved to another question: bring it into view in the paper
  focus(event) {
    const number = event.detail?.q
    if (!number) return
    this.pending = number
    this.highlight(number)
  }

  highlight(number) {
    const doc = this.bodyTarget.querySelector(".task-doc")
    if (!doc) return
    const pattern = new RegExp(`^\\s*(Q(uestion)?\\.?\\s*)?${number}\\s*[.):–-]`, "i")
    const heads = Array.from(doc.querySelectorAll("p.td-q"))
    const target = heads.find((p) => pattern.test(p.textContent))
    heads.forEach((p) => p.classList.toggle("qp-current", p === target))
    if (!target) return
    const top = target.offsetTop - 12 // .qp-body is the offset parent (position: relative)
    this.bodyTarget.scrollTo({ top: Math.max(0, top), behavior: "smooth" })
  }

  zoom(event) {
    this.scale = Math.min(1.6, Math.max(0.8, this.scale + Number(event.currentTarget.dataset.step) * 0.1))
    this.bodyTarget.style.setProperty("--qp-scale", this.scale.toFixed(2))
  }

  message(text) {
    const p = document.createElement("p")
    p.className = "tp-msg"
    p.textContent = text
    return p
  }
}
