import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    if (this.timeoutValue > 0) this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.classList.add("leaving")
    setTimeout(() => this.element.remove(), 300)
  }
}
