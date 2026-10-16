import { Controller } from "@hotwired/stimulus"

// Periodically re-renders the page (Turbo morph keeps scroll) so newly joined candidates appear.
export default class extends Controller {
  static values = { interval: { type: Number, default: 45000 } }

  connect() {
    this.timer = setInterval(() => {
      if (document.visibilityState === "visible") window.Turbo?.visit(window.location.href, { action: "replace" })
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
