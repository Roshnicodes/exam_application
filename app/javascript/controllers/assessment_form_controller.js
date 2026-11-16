import { Controller } from "@hotwired/stimulus"

// Picking the task type suggests the file types a candidate normally uploads back
// (only while HR hasn't typed their own list).
export default class extends Controller {
  static targets = [ "extensions" ]

  connect() {
    this.touched = this.hasExtensionsTarget && this.extensionsTarget.value.trim().length > 0
    if (this.hasExtensionsTarget) this.extensionsTarget.addEventListener("input", () => { this.touched = true })
  }

  kindChanged(event) {
    if (!this.hasExtensionsTarget || this.touched) return
    this.extensionsTarget.value = event.target.dataset.extensions || ""
  }
}
