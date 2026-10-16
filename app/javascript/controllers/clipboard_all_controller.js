import { Controller } from "@hotwired/stimulus"

// Copies "Name: link" for every candidate in a batch, one per line.
export default class extends Controller {
  static targets = [ "item", "label" ]

  async copy() {
    const text = this.itemTargets.map((el) => el.dataset.text).join("\n")
    try { await navigator.clipboard.writeText(text) } catch { window.prompt("Copy the links:", text) }
    this.labelTarget.textContent = `Copied ${this.itemTargets.length} links!`
    setTimeout(() => (this.labelTarget.textContent = "Copy all links"), 2500)
  }
}
