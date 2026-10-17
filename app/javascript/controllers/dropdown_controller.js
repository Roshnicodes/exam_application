import { Controller } from "@hotwired/stimulus"

// A <details> menu that closes when clicking anywhere else or pressing Escape.
export default class extends Controller {
  connect() {
    this.close = (e) => {
      if (e.type === "keydown" ? e.key === "Escape" : !this.element.contains(e.target)) this.element.open = false
    }
    document.addEventListener("click", this.close)
    document.addEventListener("keydown", this.close)
  }

  disconnect() {
    document.removeEventListener("click", this.close)
    document.removeEventListener("keydown", this.close)
  }
}
