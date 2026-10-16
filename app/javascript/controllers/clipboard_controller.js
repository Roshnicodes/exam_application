import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "source", "label" ]

  async copy() {
    const text = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.sourceTarget.select()
      document.execCommand("copy")
    }
    this.labelTarget.textContent = "Copied!"
    setTimeout(() => (this.labelTarget.textContent = "Copy link"), 2000)
  }
}
