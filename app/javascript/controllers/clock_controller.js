import { Controller } from "@hotwired/stimulus"

// Topbar clock (h:mm AM/PM), refreshed every 20 seconds.
export default class extends Controller {
  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 20000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    this.element.textContent = new Date().toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true }).toUpperCase()
  }
}
